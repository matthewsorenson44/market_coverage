import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/area_stats.dart';
import 'src/coverage.dart';
import 'src/formatting.dart';
import 'src/geo.dart';
import 'src/lead_export.dart';
import 'src/scoring.dart';

// Re-export the extracted modules so existing imports of
// `package:market_coverage/main.dart` (app code and tests) keep working.
export 'src/coverage.dart';
export 'src/area_stats.dart';
export 'src/formatting.dart';
export 'src/geo.dart';
export 'src/lead_export.dart';
export 'src/scoring.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://vwsarrsrlrhpehosajbi.supabase.co',
    anonKey: 'sb_publishable_wO0KXAR6sdbgR9RYJ2VHZQ_jX0KJ67_',
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
  );

  await FieldTestLogger.load();
  unawaited(FieldTestLogger.log('app_start'));

  runApp(const MarketCoverageApp());
}

final supabase = Supabase.instance.client;

const String defaultSessionMinutesPrefsKey = 'default_session_minutes';
const String timeMissionsEnabledPrefsKey = 'time_missions_enabled';
const String calibrationFactorPrefsKey = 'calibration_factor';
const String calibrationMissionCountPrefsKey = 'calibration_mission_count';
const String pendingLeadsQueuePrefsKey = 'pending_leads_queue';
const String activeMissionIdPrefsKey = 'active_mission_id';
const String activeCoverageCityPrefsKey = 'active_coverage_city';
const String recentMarketCitiesPrefsKey = 'recent_market_cities';
const String firstMissionTipDismissedPrefsKey = 'first_mission_tip_dismissed';
const String leadPhotosBucket = 'lead-photos';
const int maxLeadPhotoBytes = 10 * 1024 * 1024;
const int leadPhotoSignedUrlSeconds = 60 * 60 * 24 * 7;
const String defaultCoverageCity = 'Owasso';
const String motivatedSellersButtonLabel = 'Find Motivated Sellers';
const String motivatedSellersDescription =
    'Fetches every property in this area and scores them by investment potential.';
const String primaryTulsaParcelLayerUrl =
    'https://map11.incog.org/arcgis11wa/rest/services/Parcels_TulsaCo/FeatureServer/0/query';
const String fallbackTulsaParcelLayerUrl =
    'https://services3.arcgis.com/JfsWgLAOPxX7NGuG/arcgis/rest/services/Production_Map/FeatureServer/50/query';
const List<String> tulsaParcelLayerUrls = [
  primaryTulsaParcelLayerUrl,
  fallbackTulsaParcelLayerUrl,
];
const int visibleParcelZoom = 17;
const int houseNumberLabelZoom = 18;
const int visibleParcelLimit = 250;
const int marketMapMaxParcelPages = 40;
const Duration marketMapParcelPageTimeout = Duration(seconds: 20);
const Duration trackingPointMinInterval = Duration(seconds: 3);
const double trackingPointMinDistanceMiles = 0.003;
const double maxReliableLocationAccuracyMeters = 100;
const int visibleStreetLimit = 800;
const int missionStreetCount = 12;
const double streetCoverageMatchMiles = 0.035;
const double kScoutSpeedMph = 10.0;
const double kRepositioningMinutes = 1.0;
const Duration leadInsertTimeout = Duration(seconds: 8);
const Duration duplicateLeadCheckTimeout = Duration(seconds: 2);
const int targetScoreVersion = 1;
const double opportunityStreetMatchMiles = 0.04;
const Map<String, double> targetScoreWeights = {
  'out_of_state': 18,
  'absentee': 18,
  'portfolio_owner_3_plus': 18,
  'portfolio_owner_5_plus': 8,
  'low_improvement_ratio': 18,
  'long_held': 12,
  'older_build': 8,
};

final ValueNotifier<int> pendingLeadsQueueCountNotifier = ValueNotifier<int>(0);

class LeadSaveResult {
  final bool savedOnline;
  final bool queuedLocally;

  const LeadSaveResult({
    required this.savedOnline,
    required this.queuedLocally,
  });
}

class DuplicateLeadCandidate {
  final String id;
  final String address;

  const DuplicateLeadCandidate({required this.id, required this.address});
}

class QuickCaptureSaveResult {
  final Lead? lead;
  final bool queuedLocally;

  const QuickCaptureSaveResult({
    required this.lead,
    required this.queuedLocally,
  });
}

Map<String, dynamic> jsonSafeLeadRow(Map<String, dynamic> row) {
  return row.map((key, value) {
    if (value is DateTime) {
      return MapEntry(key, value.toUtc().toIso8601String());
    }

    return MapEntry(key, value);
  });
}

Future<List<Map<String, dynamic>>> pendingLeadRows() async {
  final prefs = await SharedPreferences.getInstance();
  final encoded = prefs.getString(pendingLeadsQueuePrefsKey);
  if (encoded == null || encoded.trim().isEmpty) return [];

  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) return [];

    return decoded
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  } catch (_) {
    return [];
  }
}

Future<void> savePendingLeadRows(List<Map<String, dynamic>> rows) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    pendingLeadsQueuePrefsKey,
    jsonEncode(rows.map(jsonSafeLeadRow).toList(growable: false)),
  );
  pendingLeadsQueueCountNotifier.value = rows.length;
}

Future<int> refreshPendingLeadsQueueCount() async {
  final rows = await pendingLeadRows();
  pendingLeadsQueueCountNotifier.value = rows.length;

  return rows.length;
}

Future<void> appendPendingLeadRow(Map<String, dynamic> row) async {
  final rows = await pendingLeadRows();
  rows.add(jsonSafeLeadRow(row));
  await savePendingLeadRows(rows);
}

Future<LeadSaveResult> insertLeadWithOfflineQueue(
  Map<String, dynamic> row,
) async {
  try {
    await supabase
        .from('leads')
        .insert(jsonSafeLeadRow(row))
        .timeout(leadInsertTimeout);

    return const LeadSaveResult(savedOnline: true, queuedLocally: false);
  } catch (_) {
    await appendPendingLeadRow(row);

    return const LeadSaveResult(savedOnline: false, queuedLocally: true);
  }
}

Future<void> flushPendingLeadsQueue() async {
  final rows = await pendingLeadRows();
  if (rows.isEmpty) {
    pendingLeadsQueueCountNotifier.value = 0;
    return;
  }

  unawaited(
    FieldTestLogger.log('queue_flush_start', detail: 'count: ${rows.length}'),
  );
  final remainingRows = <Map<String, dynamic>>[];
  var syncedCount = 0;

  for (final row in rows) {
    try {
      await supabase
          .from('leads')
          .insert(jsonSafeLeadRow(row))
          .timeout(leadInsertTimeout);
      syncedCount++;
    } catch (_) {
      remainingRows.add(row);
    }
  }

  await savePendingLeadRows(remainingRows);
  unawaited(
    FieldTestLogger.log('queue_flush_done', detail: 'synced: $syncedCount'),
  );
}

class FieldTestLogger {
  static const String _prefsKey = 'field_test_log';
  static const int _limit = 200;
  static final List<Map<String, String?>> _entries = [];
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<Map<String, String?>> get entries => List.unmodifiable(_entries);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(_prefsKey);
      if (encoded == null || encoded.trim().isEmpty) return;

      final decoded = jsonDecode(encoded);
      if (decoded is! List) return;

      _entries
        ..clear()
        ..addAll(
          decoded.whereType<Map>().map((entry) {
            return {
              'timestamp': entry['timestamp']?.toString(),
              'event': entry['event']?.toString(),
              'detail': entry['detail']?.toString(),
            };
          }),
        );
      _trim();
      revision.value++;
    } catch (_) {
      // Field-test logging must never affect app behavior.
    }
  }

  static Future<void> log(String event, {String? detail}) async {
    try {
      _entries.add({
        'timestamp': DateTime.now().toIso8601String(),
        'event': event,
        'detail': detail,
      });
      _trim();
      revision.value++;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_entries));
    } catch (_) {
      // Field-test logging must never affect app behavior.
    }
  }

  static Future<void> clear() async {
    try {
      _entries.clear();
      revision.value++;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {
      // Field-test logging must never affect app behavior.
    }
  }

  static String plainText() {
    return _entries
        .map((entry) {
          final timestamp = entry['timestamp'] ?? '';
          final event = entry['event'] ?? '';
          final detail = entry['detail'];

          return detail == null || detail.isEmpty
              ? '$timestamp  $event'
              : '$timestamp  $event  $detail';
        })
        .join('\n');
  }

  static void _trim() {
    while (_entries.length > _limit) {
      _entries.removeAt(0);
    }
  }
}

class LeadScoreData {
  final bool brokenWindows;
  final bool roofDamage;
  final bool tallGrass;
  final bool trashInYard;
  final bool exteriorWear;
  final bool vacantAppearance;
  final int score;
  final bool scoreOverride;

  const LeadScoreData({
    required this.brokenWindows,
    required this.roofDamage,
    required this.tallGrass,
    required this.trashInYard,
    required this.exteriorWear,
    required this.vacantAppearance,
    required this.score,
    required this.scoreOverride,
  });

  factory LeadScoreData.empty() {
    return const LeadScoreData(
      brokenWindows: false,
      roofDamage: false,
      tallGrass: false,
      trashInYard: false,
      exteriorWear: false,
      vacantAppearance: false,
      score: 0,
      scoreOverride: false,
    );
  }

  factory LeadScoreData.fromMap(Map<String, dynamic> map) {
    return LeadScoreData(
      brokenWindows: map['broken_windows'] ?? false,
      roofDamage: map['roof_damage'] ?? false,
      tallGrass: map['tall_grass'] ?? false,
      trashInYard: map['trash_in_yard'] ?? false,
      exteriorWear: map['exterior_wear'] ?? false,
      vacantAppearance: map['vacant_appearance'] ?? false,
      score: ((map['lead_score'] ?? 0) as num).toInt().clamp(0, 100),
      scoreOverride: map['score_override'] ?? false,
    );
  }

  LeadScoreData copyWith({
    bool? brokenWindows,
    bool? roofDamage,
    bool? tallGrass,
    bool? trashInYard,
    bool? exteriorWear,
    bool? vacantAppearance,
    int? score,
    bool? scoreOverride,
  }) {
    return LeadScoreData(
      brokenWindows: brokenWindows ?? this.brokenWindows,
      roofDamage: roofDamage ?? this.roofDamage,
      tallGrass: tallGrass ?? this.tallGrass,
      trashInYard: trashInYard ?? this.trashInYard,
      exteriorWear: exteriorWear ?? this.exteriorWear,
      vacantAppearance: vacantAppearance ?? this.vacantAppearance,
      score: score ?? this.score,
      scoreOverride: scoreOverride ?? this.scoreOverride,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'broken_windows': brokenWindows,
      'roof_damage': roofDamage,
      'tall_grass': tallGrass,
      'trash_in_yard': trashInYard,
      'exterior_wear': exteriorWear,
      'vacant_appearance': vacantAppearance,
      'lead_score': score.clamp(0, 100),
      'score_override': scoreOverride,
    };
  }
}

class LeadParcelData {
  final String ownerName;
  final String mailingAddress;
  final bool outOfStateOwner;
  final double? assessedValue;
  final String propertyType;
  final String lotSize;
  final int? yearBuilt;

  const LeadParcelData({
    required this.ownerName,
    required this.mailingAddress,
    required this.outOfStateOwner,
    required this.assessedValue,
    required this.propertyType,
    required this.lotSize,
    required this.yearBuilt,
  });

  factory LeadParcelData.fromMap(Map<String, dynamic> map) {
    return LeadParcelData(
      ownerName: map['owner_name'] ?? '',
      mailingAddress: map['mailing_address'] ?? '',
      outOfStateOwner: map['out_of_state_owner'] ?? false,
      assessedValue: map['assessed_value'] == null
          ? null
          : (map['assessed_value'] as num).toDouble(),
      propertyType: map['property_type'] ?? '',
      lotSize: map['lot_size'] ?? '',
      yearBuilt: map['year_built'] == null
          ? null
          : (map['year_built'] as num).toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'owner_name': ownerName,
      'mailing_address': mailingAddress,
      'out_of_state_owner': outOfStateOwner,
      'assessed_value': assessedValue,
      'property_type': propertyType,
      'lot_size': lotSize,
      'year_built': yearBuilt,
    };
  }
}

class LeadReminderData {
  final DateTime? lastVisitedDate;
  final DateTime? reminderDate;
  final String followUpStatus;

  const LeadReminderData({
    required this.lastVisitedDate,
    required this.reminderDate,
    required this.followUpStatus,
  });

  factory LeadReminderData.fromMap(Map<String, dynamic> map) {
    return LeadReminderData(
      lastVisitedDate: parseDateOnly(map['last_visited_date']),
      reminderDate: parseDateOnly(map['reminder_date']),
      followUpStatus: map['follow_up_status'] ?? 'None',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'last_visited_date': formatDateOnly(lastVisitedDate),
      'reminder_date': formatDateOnly(reminderDate),
      'follow_up_status': followUpStatus,
    };
  }

  LeadReminderData copyWith({
    DateTime? lastVisitedDate,
    bool clearLastVisitedDate = false,
    DateTime? reminderDate,
    bool clearReminderDate = false,
    String? followUpStatus,
  }) {
    return LeadReminderData(
      lastVisitedDate: clearLastVisitedDate
          ? null
          : lastVisitedDate ?? this.lastVisitedDate,
      reminderDate: clearReminderDate
          ? null
          : reminderDate ?? this.reminderDate,
      followUpStatus: followUpStatus ?? this.followUpStatus,
    );
  }
}

class LeadOfferData {
  final double? arv;
  final double? repairCost;
  final double? assignmentFee;

  const LeadOfferData({
    required this.arv,
    required this.repairCost,
    required this.assignmentFee,
  });

  factory LeadOfferData.fromMap(Map<String, dynamic> map) {
    return LeadOfferData(
      arv: map['arv'] == null ? null : (map['arv'] as num).toDouble(),
      repairCost: map['repair_cost'] == null
          ? null
          : (map['repair_cost'] as num).toDouble(),
      assignmentFee: map['assignment_fee'] == null
          ? null
          : (map['assignment_fee'] as num).toDouble(),
    );
  }

  double? get mao {
    if (arv == null) return null;

    return (arv! * 0.70) - (repairCost ?? 0) - (assignmentFee ?? 0);
  }

  Map<String, dynamic> toMap() {
    return {
      'arv': arv,
      'repair_cost': repairCost,
      'assignment_fee': assignmentFee,
    };
  }
}

class LeadSaleData {
  final String lastSaleDate;
  final double? lastSalePrice;
  final String deedType;
  final String documentDate;
  final String receptionNo;

  const LeadSaleData({
    required this.lastSaleDate,
    required this.lastSalePrice,
    required this.deedType,
    required this.documentDate,
    required this.receptionNo,
  });

  factory LeadSaleData.fromMap(Map<String, dynamic> map) {
    return LeadSaleData(
      lastSaleDate: map['last_sale_date'] ?? '',
      lastSalePrice: map['last_sale_price'] == null
          ? null
          : (map['last_sale_price'] as num).toDouble(),
      deedType: map['deed_type'] ?? '',
      documentDate: map['document_date'] ?? '',
      receptionNo: map['reception_no'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'last_sale_date': lastSaleDate.isEmpty ? null : lastSaleDate,
      'last_sale_price': lastSalePrice,
      'deed_type': deedType.isEmpty ? null : deedType,
      'document_date': documentDate.isEmpty ? null : documentDate,
      'reception_no': receptionNo.isEmpty ? null : receptionNo,
    };
  }
}

class Lead {
  final String id;
  final String address;
  final String condition;
  final String notes;
  final String status;
  final String source;
  final LeadScoreData scoreData;
  final LeadParcelData parcelData;
  final LeadReminderData reminderData;
  final LeadOfferData offerData;
  final LeadSaleData saleData;
  final DateTime? createdAt;
  final double? latitude;
  final double? longitude;

  Lead({
    required this.id,
    required this.address,
    required this.condition,
    required this.notes,
    this.status = 'New Lead',
    this.source = 'Driving For Dollars',
    required this.scoreData,
    required this.parcelData,
    required this.reminderData,
    required this.offerData,
    required this.saleData,
    required this.createdAt,
    this.latitude,
    this.longitude,
  });

  factory Lead.fromMap(Map<String, dynamic> map) {
    return Lead(
      id: map['id'].toString(),
      address: map['address'] ?? '',
      condition: map['condition'] ?? '',
      notes: map['notes'] ?? '',
      status: normalizeLeadStage(map['status'] ?? 'New Lead'),
      source: map['source'] ?? 'Driving For Dollars',
      scoreData: LeadScoreData.fromMap(map),
      parcelData: LeadParcelData.fromMap(map),
      reminderData: LeadReminderData.fromMap(map),
      offerData: LeadOfferData.fromMap(map),
      saleData: LeadSaleData.fromMap(map),
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString()),
      latitude: map['latitude'] == null
          ? null
          : (map['latitude'] as num).toDouble(),
      longitude: map['longitude'] == null
          ? null
          : (map['longitude'] as num).toDouble(),
    );
  }

  int get score => scoreData.score;
  double? get mao => offerData.mao;

  Lead copyWith({
    String? status,
    String? source,
    LeadScoreData? scoreData,
    LeadParcelData? parcelData,
    LeadReminderData? reminderData,
    LeadOfferData? offerData,
    LeadSaleData? saleData,
  }) {
    return Lead(
      id: id,
      address: address,
      condition: condition,
      notes: notes,
      status: status ?? this.status,
      source: source ?? this.source,
      scoreData: scoreData ?? this.scoreData,
      parcelData: parcelData ?? this.parcelData,
      reminderData: reminderData ?? this.reminderData,
      offerData: offerData ?? this.offerData,
      saleData: saleData ?? this.saleData,
      createdAt: createdAt,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

const List<String> followUpStatusOptions = [
  'None',
  'Needs Revisit',
  'Scheduled',
  'Completed',
];

const List<String> leadSourceOptions = [
  'Driving For Dollars',
  'Facebook',
  'Referral',
  'Direct Mail',
  'Cold Call',
  'Other',
];

class LeadPhoto {
  final String path;
  final String url;

  const LeadPhoto({required this.path, required this.url});
}

class ParcelProperty {
  final String? accountNo;
  final String? parcelNo;
  final String? propertyAddress;
  final String? ownerName;
  final String? mailingAddress;
  final String? mailingState;
  final String? propertyType;
  final int? yearBuilt;
  final double? squareFeet;
  final double? lotAcres;
  final double? assessedValue;
  final double? landValue;
  final double? improvementValue;
  final double? taxableValue;
  final String? saleDate;
  final double? salePrice;
  final String? deedType;
  final String? documentDate;
  final String? receptionNo;
  final double? bathrooms;
  final double? stories;
  final LatLng? centroid;
  final List<List<LatLng>> rings;
  final double? targetScore;
  final Map<String, dynamic>? scoreBreakdown;

  const ParcelProperty({
    required this.accountNo,
    required this.parcelNo,
    required this.propertyAddress,
    required this.ownerName,
    required this.mailingAddress,
    required this.mailingState,
    required this.propertyType,
    required this.yearBuilt,
    required this.squareFeet,
    required this.lotAcres,
    required this.assessedValue,
    required this.landValue,
    required this.improvementValue,
    required this.taxableValue,
    required this.saleDate,
    required this.salePrice,
    required this.deedType,
    required this.documentDate,
    required this.receptionNo,
    required this.bathrooms,
    required this.stories,
    required this.centroid,
    required this.rings,
    this.targetScore,
    this.scoreBreakdown,
  });

  factory ParcelProperty.fromArcGisFeature(Map<String, dynamic> feature) {
    final attributes =
        (feature['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
    final rings = parseParcelRings(feature['geometry']);
    final attributeCentroid = parseLatLngFromAttributes(attributes);

    return ParcelProperty(
      accountNo: cleanParcelText(
        attributes['AccountNo'] ?? attributes['ACCT_NUM'],
      ),
      parcelNo: cleanParcelText(attributes['ParcelNo']),
      propertyAddress: cleanParcelText(attributes['PropertyAddress']),
      ownerName: cleanParcelText(
        attributes['Owner'] ??
            attributes['Name1'] ??
            attributes['BusinessName'],
      ),
      mailingAddress: combineMailingAddress(attributes),
      mailingState: cleanParcelText(attributes['State']),
      propertyType: cleanParcelText(attributes['PropertyType']),
      yearBuilt: parseParcelInt(attributes['YearBuilt']),
      squareFeet: firstParcelDouble([
        attributes['ImpSFTotal'],
        attributes['SF'],
        attributes['BuiltAsSF'],
        attributes['GrossSF'],
      ]),
      lotAcres: parseParcelDouble(attributes['GrossAcre']),
      assessedValue: firstParcelDouble([
        attributes['TotalAcctValue'],
        attributes['TaxableValue'],
      ]),
      landValue: parseParcelDouble(attributes['TotalLandValue']),
      improvementValue: parseParcelDouble(attributes['TotalImpValue']),
      taxableValue: parseParcelDouble(attributes['TaxableValue']),
      saleDate: cleanParcelText(attributes['SaleDate']),
      salePrice: parseParcelDouble(attributes['SalePrice']),
      deedType: cleanParcelText(attributes['DeedType']),
      documentDate: cleanParcelText(attributes['DocumentDate']),
      receptionNo: cleanParcelText(attributes['ReceptionNo']),
      bathrooms: parseParcelDouble(attributes['Baths']),
      stories: parseParcelDouble(attributes['Stories']),
      centroid: attributeCentroid ?? polygonCentroid(rings),
      rings: rings,
      targetScore: null,
      scoreBreakdown: null,
    );
  }

  bool get outOfStateOwner {
    if (mailingState == null || mailingState!.isEmpty) return false;

    return mailingState!.toUpperCase() != 'OK';
  }

  String get displayAddress {
    return propertyAddress == null || propertyAddress!.isEmpty
        ? 'Unknown Property'
        : propertyAddress!;
  }

  String get lotSizeDisplay {
    if (lotAcres == null) return '';

    return '${formatDecimal(lotAcres)} acres';
  }

  String get leadNotes {
    final rows = [
      'Tulsa County parcel import',
      if (accountNo != null) 'Account: $accountNo',
      if (parcelNo != null) 'Parcel: $parcelNo',
      if (squareFeet != null) 'Sq ft: ${formatDecimal(squareFeet)}',
      if (bathrooms != null) 'Baths: ${formatDecimal(bathrooms)}',
      if (stories != null) 'Stories: ${formatDecimal(stories)}',
      if (landValue != null) 'Land value: ${formatMoney(landValue)}',
      if (improvementValue != null)
        'Improvement value: ${formatMoney(improvementValue)}',
      if (taxableValue != null) 'Taxable value: ${formatMoney(taxableValue)}',
      if (saleDate != null) 'Last sale date: $saleDate',
      if (salePrice != null) 'Sale price: ${formatMoney(salePrice)}',
      if (deedType != null) 'Deed type: $deedType',
      if (documentDate != null) 'Document date: $documentDate',
      if (receptionNo != null) 'Reception no: $receptionNo',
    ];

    return rows.join('\n');
  }
}

LatLng? parseLatLngFromAttributes(Map<String, dynamic> attributes) {
  final latitude = parseParcelDouble(attributes['Lat']);
  final longitude = parseParcelDouble(attributes['Long']);

  if (latitude == null || longitude == null) return null;

  return LatLng(latitude, longitude);
}

List<List<LatLng>> parseParcelRings(dynamic geometry) {
  if (geometry is! Map) return [];

  final rings = geometry['rings'];

  if (rings is! List) return [];

  return rings
      .map((ring) {
        if (ring is! List) return <LatLng>[];

        return ring
            .map((point) {
              if (point is! List || point.length < 2) return null;

              final longitude = parseParcelDouble(point[0]);
              final latitude = parseParcelDouble(point[1]);

              if (latitude == null || longitude == null) return null;

              return LatLng(latitude, longitude);
            })
            .whereType<LatLng>()
            .toList(growable: false);
      })
      .where((ring) => ring.length >= 3)
      .toList(growable: false);
}

LatLng? polygonCentroid(List<List<LatLng>> rings) {
  if (rings.isEmpty || rings.first.isEmpty) return null;

  double latitude = 0;
  double longitude = 0;
  var pointCount = 0;

  for (final point in rings.first) {
    latitude += point.latitude;
    longitude += point.longitude;
    pointCount++;
  }

  if (pointCount == 0) return null;

  return LatLng(latitude / pointCount, longitude / pointCount);
}

ParcelProperty? nearestParcel(LatLng point, List<ParcelProperty> parcels) {
  if (parcels.isEmpty) return null;

  final distance = Distance();
  ParcelProperty? closestParcel;
  var closestDistance = double.infinity;

  for (final parcel in parcels) {
    final centroid = parcel.centroid;

    if (centroid == null) continue;

    final parcelDistance = distance.as(LengthUnit.Meter, point, centroid);

    if (parcelDistance < closestDistance) {
      closestDistance = parcelDistance;
      closestParcel = parcel;
    }
  }

  return closestParcel ?? parcels.first;
}

class CityStreet {
  final String id;
  final String city;
  final String streetName;
  final List<LatLng> path;

  const CityStreet({
    required this.id,
    required this.city,
    required this.streetName,
    required this.path,
  });

  factory CityStreet.fromMap(Map<String, dynamic> map) {
    return CityStreet(
      id: map['id'].toString(),
      city: map['city']?.toString() ?? '',
      streetName: map['street_name']?.toString() ?? '',
      path: parseStreetPath(map['path']),
    );
  }
}

class CityReadiness {
  final String cityName;
  final String displayName;
  final String stateName;
  final String stateCode;
  final int? rankInState;
  final int? population;
  final double? latitude;
  final double? longitude;
  final String marketStatus;
  final int streetCount;
  final int propertyCount;
  final int targetCount;
  final int leadCount;
  final int driveAreaCount;
  final int coveredStreetCount;
  final bool parcelServiceVerified;
  final String streetImportStatus;
  final bool marketMapBuilt;
  final double ownerInfoPercent;

  const CityReadiness({
    required this.cityName,
    required this.displayName,
    required this.stateName,
    required this.stateCode,
    required this.rankInState,
    required this.population,
    required this.latitude,
    required this.longitude,
    required this.marketStatus,
    required this.streetCount,
    required this.propertyCount,
    required this.targetCount,
    required this.leadCount,
    required this.driveAreaCount,
    required this.coveredStreetCount,
    required this.parcelServiceVerified,
    required this.streetImportStatus,
    required this.marketMapBuilt,
    required this.ownerInfoPercent,
  });

  double get readinessScore {
    final streetLayerScore = streetCount < 1
        ? 0.0
        : streetCount < 500
        ? 50.0
        : 100.0;
    final parcelServiceScore = parcelServiceVerified ? 100.0 : 0.0;
    final marketMapScore = propertyCount < 1 ? 0.0 : 100.0;
    final coverageScore = streetCount < 1 ? 0.0 : 100.0;

    return streetLayerScore * 0.35 +
        parcelServiceScore * 0.25 +
        marketMapScore * 0.20 +
        ownerInfoPercent.clamp(0, 100) * 0.10 +
        coverageScore * 0.10;
  }

  String get statusLabel {
    if (streetCount > 0 && propertyCount > 0) return 'Ready';
    if (streetCount > 0 || propertyCount > 0) return 'Partial';
    if (marketStatus == 'planned') return 'Planned';
    return 'Missing Data';
  }

  Color get statusColor {
    switch (statusLabel) {
      case 'Ready':
        return Colors.green;
      case 'Partial':
        return Colors.amber;
      case 'Missing Data':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  bool get isDrivable {
    return statusLabel == 'Ready';
  }

  String get suggestedNextStep {
    if (streetCount < 1) return 'Import streets';
    if (propertyCount < 1) return 'Import properties';
    if (targetCount < 1) return 'Build Market Map';
    return 'Ready to drive';
  }
}

class Market {
  final String id;
  final String city;
  final String state;
  final String stateCode;
  final String? county;
  final String displayName;
  final String? metro;
  final int? population;
  final int? metroRank;
  final int? stateRank;
  final String? parcelServiceUrl;
  final int parcelServiceLayer;
  final String parcelWhereClause;
  final String streetDataStatus;
  final String propertyDataStatus;
  final String targetDataStatus;
  final String readinessStatus;
  final int cachedStreetCount;
  final int cachedPropertyCount;
  final int cachedTargetCount;
  final DateTime? streetsLastImportedAt;
  final DateTime? propertiesLastImportedAt;
  final DateTime? targetsLastComputedAt;
  final DateTime? lastImportedAt;
  final int rolloutOrder;
  final bool isActiveMarket;
  final bool isVisibleInApp;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Market({
    required this.id,
    required this.city,
    required this.state,
    required this.stateCode,
    required this.county,
    required this.displayName,
    required this.metro,
    required this.population,
    required this.metroRank,
    required this.stateRank,
    required this.parcelServiceUrl,
    required this.parcelServiceLayer,
    required this.parcelWhereClause,
    required this.streetDataStatus,
    required this.propertyDataStatus,
    required this.targetDataStatus,
    required this.readinessStatus,
    required this.cachedStreetCount,
    required this.cachedPropertyCount,
    required this.cachedTargetCount,
    required this.streetsLastImportedAt,
    required this.propertiesLastImportedAt,
    required this.targetsLastComputedAt,
    required this.lastImportedAt,
    required this.rolloutOrder,
    required this.isActiveMarket,
    required this.isVisibleInApp,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Market.fromMap(Map<String, dynamic> map) {
    int intValue(String key, [int fallback = 0]) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    int? nullableInt(String key) {
      final value = map[key];
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    DateTime? dateValue(String key) {
      final value = map[key];
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    final city = map['city']?.toString() ?? '';
    final stateCode = map['state_code']?.toString() ?? '';
    final displayName = map['display_name']?.toString();

    return Market(
      id: map['id']?.toString() ?? '',
      city: city,
      state: map['state']?.toString() ?? '',
      stateCode: stateCode,
      county: map['county']?.toString(),
      displayName: displayName == null || displayName.trim().isEmpty
          ? stateCode.isEmpty
                ? city
                : '$city, $stateCode'
          : displayName,
      metro: map['metro']?.toString(),
      population: nullableInt('population'),
      metroRank: nullableInt('metro_rank'),
      stateRank: nullableInt('state_rank'),
      parcelServiceUrl: map['parcel_service_url']?.toString(),
      parcelServiceLayer: intValue('parcel_service_layer'),
      parcelWhereClause:
          map['parcel_where_clause']?.toString() ??
          "PAR_TYPE IN ('PARCEL','CONDO')",
      streetDataStatus: map['street_data_status']?.toString() ?? 'none',
      propertyDataStatus: map['property_data_status']?.toString() ?? 'none',
      targetDataStatus: map['target_data_status']?.toString() ?? 'none',
      readinessStatus: map['readiness_status']?.toString() ?? 'planned',
      cachedStreetCount: intValue('cached_street_count'),
      cachedPropertyCount: intValue('cached_property_count'),
      cachedTargetCount: intValue('cached_target_count'),
      streetsLastImportedAt: dateValue('streets_last_imported_at'),
      propertiesLastImportedAt: dateValue('properties_last_imported_at'),
      targetsLastComputedAt: dateValue('targets_last_computed_at'),
      lastImportedAt: dateValue('last_imported_at'),
      rolloutOrder: intValue('rollout_order', 999),
      isActiveMarket: map['is_active_market'] == true,
      isVisibleInApp: map['is_visible_in_app'] != false,
      notes: map['notes']?.toString(),
      createdAt: dateValue('created_at'),
      updatedAt: dateValue('updated_at'),
    );
  }

  Color get statusColor {
    if (readinessStatus == 'ready') return Colors.green;
    if (readinessStatus == 'partial') return Colors.amber;
    if (streetDataStatus == 'none' && propertyDataStatus != 'none') {
      return Colors.orange;
    }
    return Colors.grey;
  }

  String get statusLabel {
    if (readinessStatus == 'ready') return 'Ready';
    if (readinessStatus == 'partial') return 'Partial';
    if (streetDataStatus == 'none' && propertyDataStatus != 'none') {
      return 'Building';
    }
    return 'Planned';
  }

  bool get isDrivable {
    return readinessStatus == 'ready' ||
        (cachedStreetCount >= 500 && parcelServiceUrl != null);
  }

  String get nextAction {
    if (isDrivable) return 'Ready to drive';
    if (streetDataStatus == 'none') return 'Import streets to unlock missions';
    if (propertyDataStatus == 'none') {
      return 'Build Market Map to unlock targets';
    }
    if (targetDataStatus == 'none') return 'Run target scoring';
    return 'Verify data quality';
  }
}

class MarketDataHealth {
  final int streetCount;
  final int propertyCount;
  final int targetCount;
  final int leadCount;
  final int driveAreaCount;
  final int missionCount;

  const MarketDataHealth({
    required this.streetCount,
    required this.propertyCount,
    required this.targetCount,
    required this.leadCount,
    required this.driveAreaCount,
    required this.missionCount,
  });

  List<String> get missingLayers {
    final missing = <String>[];
    if (streetCount == 0) missing.add('Street centerlines are missing');
    if (propertyCount == 0) missing.add('Property data is missing');
    if (targetCount == 0) missing.add('Target scores are missing');
    if (leadCount == 0) missing.add('No leads found in this market');
    if (driveAreaCount == 0) missing.add('No drive areas exist yet');
    if (missionCount == 0) missing.add('No missions have been created');
    return missing;
  }

  String get primaryNextAction {
    if (streetCount == 0) return 'Import streets to unlock missions';
    if (propertyCount == 0) return 'Build Market Map to unlock targets';
    if (targetCount == 0) return 'Run target scoring';
    if (driveAreaCount == 0) return 'Create a drive area';
    if (missionCount == 0) return 'Start the first mission';
    if (leadCount == 0) return 'Capture leads in the market';
    return 'Verify data quality';
  }
}

class MarketService {
  static Market? _activeMarketCache;
  static List<Market>? _allMarketsCache;
  static DateTime? _cacheTime;
  static String _activeCityCache = defaultCoverageCity;

  static bool get _cacheIsFresh {
    final cacheTime = _cacheTime;
    return cacheTime != null &&
        DateTime.now().difference(cacheTime) < const Duration(minutes: 5);
  }

  static Future<List<Market>> loadAllMarkets() async {
    if (_allMarketsCache != null && _cacheIsFresh) return _allMarketsCache!;

    final data = await supabase
        .from('markets')
        .select()
        .eq('is_visible_in_app', true)
        .order('rollout_order', ascending: true);
    final markets = data
        .map<Market>((item) => Market.fromMap(item))
        .toList(growable: false);

    _allMarketsCache = markets;
    _cacheTime = DateTime.now();
    _activeMarketCache = markets
        .where((market) => market.city == _activeCityCache)
        .firstOrNull;

    return markets;
  }

  static Future<List<Market>> loadMarketsByState(String stateCode) async {
    final markets = await loadAllMarkets();
    return markets
        .where((market) => market.stateCode == stateCode)
        .toList(growable: false);
  }

  static Future<Market?> loadMarket(String city, String stateCode) async {
    final activeMarket = _activeMarketCache;
    if (activeMarket != null &&
        activeMarket.city == city &&
        activeMarket.stateCode == stateCode) {
      return activeMarket;
    }

    final markets = await loadAllMarkets();
    final cached = markets
        .where((market) => market.city == city && market.stateCode == stateCode)
        .firstOrNull;
    if (cached != null) return cached;

    final data = await supabase
        .from('markets')
        .select()
        .eq('city', city)
        .eq('state_code', stateCode)
        .maybeSingle();
    if (data == null) return null;
    return Market.fromMap(data);
  }

  static Future<MarketDataHealth> loadMarketHealth(Market market) async {
    final streetCount = await supabase
        .from('city_streets')
        .count()
        .ilike('city', market.city);
    final driveAreaRows = await supabase
        .from('drive_areas')
        .select('id')
        .ilike('city', market.city);
    final driveAreaCount = await supabase
        .from('drive_areas')
        .count()
        .ilike('city', market.city);
    final driveAreaIds = driveAreaRows
        .map<String>((row) => row['id'].toString())
        .toList(growable: false);
    final propertyCount = driveAreaIds.isEmpty
        ? 0
        : await supabase
              .from('properties')
              .count()
              .inFilter('drive_area_id', driveAreaIds);
    final targetCount = driveAreaIds.isEmpty
        ? 0
        : await supabase
              .from('properties')
              .count()
              .inFilter('drive_area_id', driveAreaIds)
              .not('target_score', 'is', null);
    final leadCount = await supabase
        .from('leads')
        .count()
        .ilike('address', '%${market.city}%');
    final missionCount = driveAreaIds.isEmpty
        ? 0
        : await supabase
              .from('missions')
              .count()
              .inFilter('drive_area_id', driveAreaIds);

    return MarketDataHealth(
      streetCount: streetCount,
      propertyCount: propertyCount,
      targetCount: targetCount,
      leadCount: leadCount,
      driveAreaCount: driveAreaCount,
      missionCount: missionCount,
    );
  }

  static String getActiveCity() {
    return _activeCityCache.trim().isEmpty
        ? defaultCoverageCity
        : _activeCityCache;
  }

  static Future<void> setActiveCity(String city) async {
    final activeCity = city.trim().isEmpty ? defaultCoverageCity : city.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(activeCoverageCityPrefsKey, activeCity);
    _activeCityCache = activeCity;
    _activeMarketCache = _allMarketsCache
        ?.where((market) => market.city == activeCity)
        .firstOrNull;
  }

  static Future<void> initActiveCity() async {
    final prefs = await SharedPreferences.getInstance();
    final activeCity = prefs.getString(activeCoverageCityPrefsKey);
    _activeCityCache = activeCity == null || activeCity.trim().isEmpty
        ? defaultCoverageCity
        : activeCity;
  }
}

class DrivingPoint {
  final LatLng point;
  final DateTime? createdAt;
  final String? driveSessionId;

  const DrivingPoint({
    required this.point,
    required this.createdAt,
    required this.driveSessionId,
  });

  factory DrivingPoint.fromMap(Map<String, dynamic> map) {
    return DrivingPoint(
      point: LatLng(
        (map['latitude'] as num).toDouble(),
        (map['longitude'] as num).toDouble(),
      ),
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString()),
      driveSessionId: map['drive_session_id']?.toString(),
    );
  }
}

String leadPrimaryLabel(Lead lead) {
  final ownerName = lead.parcelData.ownerName.trim();
  if (ownerName.isNotEmpty) return ownerName;

  final address = lead.address.trim();
  if (address.isNotEmpty) return address;

  return 'Unnamed lead';
}

String leadSecondaryLabel(Lead lead) {
  final ownerName = lead.parcelData.ownerName.trim();
  final address = lead.address.trim();

  if (ownerName.isNotEmpty && address.isNotEmpty) return address;

  final condition = lead.condition.trim();
  if (condition.isNotEmpty) return condition;

  return normalizeLeadStage(lead.status);
}

bool leadNeedsMissionFollowUp(Lead lead) {
  final stage = normalizeLeadStage(lead.status);
  if (stage == 'Closed' || stage == 'Dead Lead') return false;

  return lead.reminderData.followUpStatus != 'Completed';
}

List<Lead> prioritizedMissionFollowUpLeads(Iterable<Lead> leads) {
  final prioritized = leads.where(leadNeedsMissionFollowUp).toList();

  prioritized.sort((a, b) {
    final scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) return scoreCompare;

    final aHasReminder = a.reminderData.reminderDate != null;
    final bHasReminder = b.reminderData.reminderDate != null;
    if (aHasReminder != bHasReminder) return aHasReminder ? 1 : -1;

    return leadPrimaryLabel(a).compareTo(leadPrimaryLabel(b));
  });

  return prioritized;
}

String missionLeadFollowUpLabel(Lead lead) {
  final status = lead.reminderData.followUpStatus;
  final reminderDate = lead.reminderData.reminderDate;

  if (status == 'None' && reminderDate == null) return 'No reminder set';
  if (reminderDate == null) return status;

  return '$status - ${displayDate(reminderDate)}';
}

String missionNextActionSummary({
  required int leadCount,
  required int priorityLeadCount,
  required int areaRemainingEstimatedMinutes,
}) {
  if (leadCount == 0 && areaRemainingEstimatedMinutes <= 0) {
    return 'No new leads from this mission, and the area is estimated complete. Review the map or create a fresh area.';
  }

  if (leadCount == 0) {
    return 'No leads from this mission. Start the next session or tighten the target filters before covering the remaining streets.';
  }

  if (priorityLeadCount == 0) {
    return 'All mission leads are already closed or completed. Check the remaining area before starting the next drive.';
  }

  if (priorityLeadCount == 1) {
    return 'Review the top lead from this drive and set a follow-up before starting another mission.';
  }

  return 'Review $priorityLeadCount open leads from this drive. Work the highest scores first, then plan the next uncovered streets.';
}

int missionStreetTotalFor(Mission? mission) {
  if (mission == null) return 0;
  return math.max(mission.streetCount, mission.targetStreetIds.length);
}

int missionCoveredStreetCount(Mission? mission, Set<String> coveredStreetIds) {
  if (mission == null) return 0;
  return mission.targetStreetIds
      .where((streetId) => coveredStreetIds.contains(streetId))
      .length
      .clamp(0, missionStreetTotalFor(mission))
      .toInt();
}

double safeMissionOpportunityCaptured({
  required double opportunityAtStart,
  required double opportunityRemaining,
}) {
  if (opportunityAtStart <= 0) return 0;
  return (opportunityAtStart - opportunityRemaining).clamp(
    0.0,
    opportunityAtStart,
  );
}

double safePercent(int part, int total) {
  if (total <= 0) return 0;
  return (part.clamp(0, total) / total) * 100;
}

bool isLowAccuracyPosition(Position position) {
  return position.accuracy > maxReliableLocationAccuracyMeters;
}

String lowAccuracyLocationMessage(Position position) {
  return 'GPS accuracy is low (${position.accuracy.toStringAsFixed(0)}m). Move outside or wait a few seconds for a better signal.';
}

String? leadParcelDedupKey(Lead lead) {
  final notes = lead.notes;
  final parcelMatch = RegExp(
    r'^\s*Parcel:\s*([A-Za-z0-9_-]+)\s*$',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(notes);

  if (parcelMatch != null) {
    final parcelId = parcelMatch.group(1)?.trim();
    if (parcelId != null && parcelId.isNotEmpty) {
      return 'parcel:${parcelId.toLowerCase()}';
    }
  }

  final accountMatch = RegExp(
    r'^\s*Account:\s*([A-Za-z0-9_-]+)\s*$',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(notes);

  if (accountMatch != null) {
    final accountId = accountMatch.group(1)?.trim();
    if (accountId != null && accountId.isNotEmpty) {
      return 'account:${accountId.toLowerCase()}';
    }
  }

  return null;
}

String leadDisplayDedupKey(Lead lead) {
  final parcelKey = leadParcelDedupKey(lead);
  if (parcelKey != null) return parcelKey;

  final addressKey = normalizedAddressKey(lead.address);
  if (addressKey.isNotEmpty) return 'address:$addressKey';

  return 'id:${lead.id}';
}

bool shouldPreferLeadForDisplay(Lead candidate, Lead existing) {
  if (candidate.score != existing.score) {
    return candidate.score > existing.score;
  }

  final candidateDate = candidate.createdAt;
  final existingDate = existing.createdAt;
  if (candidateDate != null && existingDate != null) {
    return candidateDate.isAfter(existingDate);
  }

  return candidateDate != null && existingDate == null;
}

List<Lead> dedupeLeadsForDisplay(Iterable<Lead> leads) {
  final dedupedByKey = <String, Lead>{};

  for (final lead in leads) {
    final key = leadDisplayDedupKey(lead);
    final existing = dedupedByKey[key];
    if (existing == null || shouldPreferLeadForDisplay(lead, existing)) {
      dedupedByKey[key] = lead;
    }
  }

  final deduped = dedupedByKey.values.toList(growable: false);
  deduped.sort((a, b) => b.score.compareTo(a.score));
  return deduped;
}

String mapModeLabel(String mode) {
  return switch (mode) {
    'targets' => 'Targets',
    'coverage' => 'Coverage',
    'drive' => 'Drive',
    _ => 'Mission Drive',
  };
}

String mapModeDescription(String mode) {
  return switch (mode) {
    'targets' => 'Scored parcels, target filters, and lead markers.',
    'coverage' => 'Covered streets, remaining streets, and next uncovered.',
    'drive' => 'Lightweight parcel tapping and route tracking.',
    _ => 'Next mission street, route, opportunity heat, and leads.',
  };
}

IconData mapModeIcon(String mode) {
  return switch (mode) {
    'targets' => Icons.adjust,
    'coverage' => Icons.timeline,
    'drive' => Icons.directions_car,
    _ => Icons.flag,
  };
}

class DriveArea {
  final String id;
  final String name;
  final String city;
  final List<LatLng> polygon;
  final String status;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? completedAt;

  const DriveArea({
    required this.id,
    required this.name,
    required this.city,
    required this.polygon,
    required this.status,
    required this.isActive,
    required this.createdAt,
    required this.completedAt,
  });

  factory DriveArea.fromMap(Map<String, dynamic> map) {
    return DriveArea(
      id: map['id'].toString(),
      name: map['name']?.toString() ?? 'Untitled area',
      city: map['city']?.toString() ?? '',
      polygon: parseDriveAreaPolygon(map['polygon']),
      status: map['status']?.toString() ?? 'in_progress',
      isActive: map['is_active'] == true,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString()),
      completedAt: map['completed_at'] == null
          ? null
          : DateTime.tryParse(map['completed_at'].toString()),
    );
  }

  bool get isComplete => status == 'complete';
}

class MarketProperty {
  final String id;
  final String driveAreaId;
  final ParcelProperty parcel;
  final bool outOfState;
  final bool absentee;
  final Map<String, dynamic> signals;
  final double targetScore;
  final Map<String, dynamic> scoreBreakdown;
  final bool hasStoredScore;

  const MarketProperty({
    required this.id,
    required this.driveAreaId,
    required this.parcel,
    required this.outOfState,
    required this.absentee,
    required this.signals,
    required this.targetScore,
    required this.scoreBreakdown,
    required this.hasStoredScore,
  });

  factory MarketProperty.fromMap(Map<String, dynamic> map) {
    final latitude = (map['latitude'] as num?)?.toDouble();
    final longitude = (map['longitude'] as num?)?.toDouble();
    final targetScore = (map['target_score'] as num?)?.toDouble() ?? 0;
    final scoreBreakdown =
        (map['score_breakdown'] as Map?)?.cast<String, dynamic>() ?? {};

    return MarketProperty(
      id: map['id'].toString(),
      driveAreaId: map['drive_area_id']?.toString() ?? '',
      parcel: ParcelProperty(
        accountNo: map['account_no']?.toString(),
        parcelNo: null,
        propertyAddress: map['address']?.toString(),
        ownerName: map['owner_name']?.toString(),
        mailingAddress: map['mailing_address']?.toString(),
        mailingState: map['mailing_state']?.toString(),
        propertyType: map['property_type']?.toString(),
        yearBuilt: (map['year_built'] as num?)?.toInt(),
        squareFeet: (map['square_feet'] as num?)?.toDouble(),
        lotAcres: (map['lot_acres'] as num?)?.toDouble(),
        assessedValue: (map['assessed_value'] as num?)?.toDouble(),
        landValue: (map['land_value'] as num?)?.toDouble(),
        improvementValue: (map['improvement_value'] as num?)?.toDouble(),
        taxableValue: null,
        saleDate: map['last_sale_date']?.toString(),
        salePrice: (map['last_sale_price'] as num?)?.toDouble(),
        deedType: null,
        documentDate: null,
        receptionNo: null,
        bathrooms: null,
        stories: null,
        centroid: latitude == null || longitude == null
            ? null
            : LatLng(latitude, longitude),
        rings: parseStoredParcelRings(map['rings']),
        targetScore: targetScore,
        scoreBreakdown: scoreBreakdown,
      ),
      outOfState: map['out_of_state'] == true,
      absentee: map['absentee'] == true,
      signals: (map['signals'] as Map?)?.cast<String, dynamic>() ?? {},
      targetScore: targetScore,
      scoreBreakdown: scoreBreakdown,
      hasStoredScore: map['target_score'] != null,
    );
  }

  int get portfolioCount => ((signals['portfolio_count'] ?? 0) as num).toInt();

  bool get lowImprovementRatio => signals['low_improvement_ratio'] == true;
}

class StreetOpportunity {
  final CityStreet street;
  final double score;
  final bool isCovered;

  const StreetOpportunity({
    required this.street,
    required this.score,
    required this.isCovered,
  });
}

class Mission {
  final String id;
  final String driveAreaId;
  final String status;
  final List<String> targetStreetIds;
  final int streetCount;
  final double opportunityAtStart;
  final int? leadsGenerated;
  final double? milesDriven;
  final int? streetsCovered;
  final double? opportunityCaptured;
  final int? timeBudgetMinutes;
  final int? estimatedMinutes;
  final int? actualMinutes;
  final DateTime? scheduledDate;
  final String? weeklyPlanId;
  final String? driveSessionId;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final double? missionStartLat;
  final double? missionStartLng;
  final DateTime? missionStartedAt;
  final DateTime? completedAt;

  const Mission({
    required this.id,
    required this.driveAreaId,
    required this.status,
    required this.targetStreetIds,
    required this.streetCount,
    required this.opportunityAtStart,
    required this.leadsGenerated,
    required this.milesDriven,
    required this.streetsCovered,
    required this.opportunityCaptured,
    required this.timeBudgetMinutes,
    required this.estimatedMinutes,
    required this.actualMinutes,
    required this.scheduledDate,
    required this.weeklyPlanId,
    required this.driveSessionId,
    required this.createdAt,
    required this.startedAt,
    required this.missionStartLat,
    required this.missionStartLng,
    required this.missionStartedAt,
    required this.completedAt,
  });

  factory Mission.fromMap(Map<String, dynamic> map) {
    return Mission(
      id: map['id'].toString(),
      driveAreaId: map['drive_area_id']?.toString() ?? '',
      status: map['status']?.toString() ?? 'active',
      targetStreetIds: parseMissionStreetIds(map['target_street_ids']),
      streetCount: ((map['street_count'] ?? 0) as num).toInt(),
      opportunityAtStart: ((map['opportunity_at_start'] ?? 0) as num)
          .toDouble(),
      leadsGenerated: map['leads_generated'] == null
          ? null
          : (map['leads_generated'] as num).toInt(),
      milesDriven: map['miles_driven'] == null
          ? null
          : (map['miles_driven'] as num).toDouble(),
      streetsCovered: map['streets_covered'] == null
          ? null
          : (map['streets_covered'] as num).toInt(),
      opportunityCaptured: map['opportunity_captured'] == null
          ? null
          : (map['opportunity_captured'] as num).toDouble(),
      timeBudgetMinutes: map['time_budget_minutes'] == null
          ? null
          : (map['time_budget_minutes'] as num).toInt(),
      estimatedMinutes: map['estimated_minutes'] == null
          ? null
          : (map['estimated_minutes'] as num).toInt(),
      actualMinutes: map['actual_minutes'] == null
          ? null
          : (map['actual_minutes'] as num).toInt(),
      scheduledDate: map['scheduled_date'] == null
          ? null
          : DateTime.tryParse(map['scheduled_date'].toString()),
      weeklyPlanId: map['weekly_plan_id']?.toString(),
      driveSessionId: map['drive_session_id']?.toString(),
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString()),
      startedAt: map['started_at'] == null
          ? null
          : DateTime.tryParse(map['started_at'].toString()),
      missionStartLat: parseCoordinate(map['mission_start_lat']),
      missionStartLng: parseCoordinate(map['mission_start_lng']),
      missionStartedAt: map['mission_started_at'] == null
          ? null
          : DateTime.tryParse(map['mission_started_at'].toString()),
      completedAt: map['completed_at'] == null
          ? null
          : DateTime.tryParse(map['completed_at'].toString()),
    );
  }

  LatLng? get missionStartPoint {
    final lat = missionStartLat;
    final lng = missionStartLng;
    if (lat == null || lng == null) return null;

    return LatLng(lat, lng);
  }

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isScheduled => status == 'scheduled';
  bool get isSkipped => status == 'skipped';
  bool get isOpen => isActive || isPaused;
}

List<String> parseMissionStreetIds(dynamic value) {
  if (value is! List) return [];

  return value.map((item) => item.toString()).toList(growable: false);
}

List<LatLng> parseDriveAreaPolygon(dynamic value) {
  if (value is! List) return [];

  return value
      .map(parseStreetPoint)
      .whereType<LatLng>()
      .toList(growable: false);
}

List<Map<String, double>> driveAreaPolygonToJson(List<LatLng> polygon) {
  return polygon
      .map((point) => {'lat': point.latitude, 'lng': point.longitude})
      .toList(growable: false);
}

List<List<Map<String, double>>> parcelRingsToJson(List<List<LatLng>> rings) {
  return rings
      .map(
        (ring) => ring
            .map((point) => {'lat': point.latitude, 'lng': point.longitude})
            .toList(growable: false),
      )
      .toList(growable: false);
}

List<List<LatLng>> parseStoredParcelRings(dynamic value) {
  if (value is! List) return [];

  return value
      .map((ring) {
        if (ring is! List) return <LatLng>[];

        return ring.map(parseStreetPoint).whereType<LatLng>().toList();
      })
      .where((ring) => ring.length >= 3)
      .toList(growable: false);
}

bool streetFallsInsidePolygon(CityStreet street, List<LatLng> polygon) {
  if (polygon.length < 3 || street.path.isEmpty) return false;

  for (final point in street.path) {
    if (pointInRing(point, polygon)) return true;
  }

  for (var index = 1; index < street.path.length; index++) {
    final midpoint = LatLng(
      (street.path[index - 1].latitude + street.path[index].latitude) / 2,
      (street.path[index - 1].longitude + street.path[index].longitude) / 2,
    );

    if (pointInRing(midpoint, polygon)) return true;
  }

  return false;
}

({double score, Map<String, dynamic> breakdown}) targetScoreForSignals(
  Map<String, dynamic> signals,
) {
  final contributions = <Map<String, dynamic>>[];
  var score = 0.0;

  void addContribution(String label, String key, bool applies) {
    final points = applies ? (targetScoreWeights[key] ?? 0) : 0.0;
    score += points;
    contributions.add({
      'label': label,
      'key': key,
      'applies': applies,
      'points': points,
    });
  }

  final portfolioCount = ((signals['portfolio_count'] ?? 0) as num).toInt();

  addContribution(
    'Out-of-state owner',
    'out_of_state',
    signals['out_of_state'] == true,
  );
  addContribution('Absentee owner', 'absentee', signals['absentee'] == true);
  addContribution(
    'Portfolio owner 3+',
    'portfolio_owner_3_plus',
    portfolioCount >= 3,
  );
  addContribution(
    'Portfolio owner 5+ bonus',
    'portfolio_owner_5_plus',
    portfolioCount >= 5,
  );
  addContribution(
    'Low improvement ratio',
    'low_improvement_ratio',
    signals['low_improvement_ratio'] == true,
  );
  addContribution('Long held', 'long_held', signals['long_held'] == true);
  addContribution('Older build', 'older_build', signals['older_build'] == true);

  final clampedScore = score.clamp(0, 100).toDouble();

  return (
    score: clampedScore,
    breakdown: {
      'version': targetScoreVersion,
      'score': clampedScore,
      'weights': targetScoreWeights,
      'contributions': contributions,
    },
  );
}

Color targetScoreColor(double score) {
  if (score >= 70) return const Color(0xFFC62828);
  if (score >= 40) return const Color(0xFFF9A825);
  return const Color(0xFF2E7D32);
}

double remainingOpportunityForArea(
  List<MarketProperty> properties,
  List<CityStreet> activeAreaStreets,
  Set<String> coveredStreetIds,
) {
  if (properties.isEmpty) return 0;

  final coveredStreets = activeAreaStreets
      .where((street) => coveredStreetIds.contains(street.id))
      .toList();

  var remaining = 0.0;

  for (final property in properties) {
    final centroid = property.parcel.centroid;

    if (centroid == null) continue;

    final covered = coveredStreets.any(
      (street) =>
          distanceToStreetMiles(centroid, street) <=
          opportunityStreetMatchMiles,
    );

    if (!covered) remaining += property.targetScore;
  }

  return remaining;
}

const double maxRoutePointGapMiles = 0.5;

LatLng? parseStreetPoint(dynamic value) {
  if (value is Map) {
    final latitude = parseCoordinate(value['lat'] ?? value['latitude']);
    final longitude = parseCoordinate(
      value['lng'] ?? value['lon'] ?? value['longitude'],
    );

    if (latitude == null || longitude == null) return null;

    return LatLng(latitude, longitude);
  }

  if (value is List && value.length >= 2) {
    final latitude = parseCoordinate(value[0]);
    final longitude = parseCoordinate(value[1]);

    if (latitude == null || longitude == null) return null;

    return LatLng(latitude, longitude);
  }

  return null;
}

List<LatLng> parseStreetPath(dynamic value) {
  if (value is! List) return [];

  return value
      .map(parseStreetPoint)
      .whereType<LatLng>()
      .toList(growable: false);
}

double pointToStreetSegmentMiles(
  LatLng point,
  LatLng segmentStart,
  LatLng segmentEnd,
) {
  final averageLatitudeRadians =
      (point.latitude + segmentStart.latitude + segmentEnd.latitude) /
      3 *
      math.pi /
      180;
  final longitudeMiles = math.cos(averageLatitudeRadians) * 69.0;

  final pointX = point.longitude * longitudeMiles;
  final pointY = point.latitude * 69.0;
  final startX = segmentStart.longitude * longitudeMiles;
  final startY = segmentStart.latitude * 69.0;
  final endX = segmentEnd.longitude * longitudeMiles;
  final endY = segmentEnd.latitude * 69.0;

  final deltaX = endX - startX;
  final deltaY = endY - startY;
  final segmentLengthSquared = (deltaX * deltaX) + (deltaY * deltaY);

  if (segmentLengthSquared == 0) {
    final xDistance = pointX - startX;
    final yDistance = pointY - startY;

    return math.sqrt((xDistance * xDistance) + (yDistance * yDistance));
  }

  final projection =
      (((pointX - startX) * deltaX) + ((pointY - startY) * deltaY)) /
      segmentLengthSquared;
  final segmentPosition = projection.clamp(0.0, 1.0);
  final closestX = startX + (segmentPosition * deltaX);
  final closestY = startY + (segmentPosition * deltaY);
  final xDistance = pointX - closestX;
  final yDistance = pointY - closestY;

  return math.sqrt((xDistance * xDistance) + (yDistance * yDistance));
}

double distanceToStreetMiles(LatLng point, CityStreet street) {
  if (street.path.isEmpty) return double.infinity;

  if (street.path.length == 1) {
    return Distance().as(LengthUnit.Mile, point, street.path.first);
  }

  var closestDistance = double.infinity;

  for (var index = 1; index < street.path.length; index++) {
    final distance = pointToStreetSegmentMiles(
      point,
      street.path[index - 1],
      street.path[index],
    );

    if (distance < closestDistance) {
      closestDistance = distance;
    }
  }

  return closestDistance;
}

({double minLat, double maxLat, double minLng, double maxLng})? latLngBounds(
  List<LatLng> points,
) {
  if (points.isEmpty) return null;

  var minLat = points.first.latitude;
  var maxLat = points.first.latitude;
  var minLng = points.first.longitude;
  var maxLng = points.first.longitude;

  for (final point in points.skip(1)) {
    minLat = math.min(minLat, point.latitude);
    maxLat = math.max(maxLat, point.latitude);
    minLng = math.min(minLng, point.longitude);
    maxLng = math.max(maxLng, point.longitude);
  }

  return (minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng);
}

bool pointNearLatLngBounds(
  LatLng point,
  ({double minLat, double maxLat, double minLng, double maxLng}) bounds,
  double bufferMiles,
) {
  final latBuffer = bufferMiles / 69.0;
  final averageLatitudeRadians =
      ((bounds.minLat + bounds.maxLat) / 2) * math.pi / 180;
  final lngMiles = math.max(1.0, math.cos(averageLatitudeRadians).abs() * 69.0);
  final lngBuffer = bufferMiles / lngMiles;

  return point.latitude >= bounds.minLat - latBuffer &&
      point.latitude <= bounds.maxLat + latBuffer &&
      point.longitude >= bounds.minLng - lngBuffer &&
      point.longitude <= bounds.maxLng + lngBuffer;
}

String drivingPointDateKey(DrivingPoint drivingPoint) {
  final localDate = drivingPoint.createdAt?.toLocal();

  if (localDate == null) return 'unknown';

  return '${localDate.year}-${localDate.month}-${localDate.day}';
}

String drivingPointRouteKey(DrivingPoint drivingPoint) {
  if (drivingPoint.driveSessionId != null &&
      drivingPoint.driveSessionId!.isNotEmpty) {
    return 'session:${drivingPoint.driveSessionId}';
  }

  return 'date:${drivingPointDateKey(drivingPoint)}';
}

List<List<LatLng>> splitRouteSegments(List<LatLng> points) {
  if (points.length < 2) return [];

  final distance = Distance();
  final segments = <List<LatLng>>[];
  var currentSegment = <LatLng>[points.first];

  for (var index = 1; index < points.length; index++) {
    final previousPoint = points[index - 1];
    final currentPoint = points[index];
    final gapMiles = distance.as(LengthUnit.Mile, previousPoint, currentPoint);

    if (gapMiles > maxRoutePointGapMiles) {
      if (currentSegment.length > 1) {
        segments.add(currentSegment);
      }

      currentSegment = [currentPoint];
    } else {
      currentSegment.add(currentPoint);
    }
  }

  if (currentSegment.length > 1) {
    segments.add(currentSegment);
  }

  return segments;
}

double routeMiles(List<LatLng> points) {
  final distance = Distance();
  double miles = 0;

  for (final segment in splitRouteSegments(points)) {
    for (var index = 1; index < segment.length; index++) {
      miles += distance.as(LengthUnit.Mile, segment[index - 1], segment[index]);
    }
  }

  return miles;
}

double estimateStreetMinutes(CityStreet street) {
  final distance = Distance();
  double miles = 0;

  for (var index = 1; index < street.path.length; index++) {
    miles += distance.as(
      LengthUnit.Mile,
      street.path[index - 1],
      street.path[index],
    );
  }

  return (miles / kScoutSpeedMph * 60) + kRepositioningMinutes;
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String isoDateOnly(DateTime date) {
  final normalized = dateOnly(date);
  final month = normalized.month.toString().padLeft(2, '0');
  final day = normalized.day.toString().padLeft(2, '0');

  return '${normalized.year}-$month-$day';
}

bool isSameCalendarDate(DateTime? a, DateTime b) {
  if (a == null) return false;

  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String shortWeekdayLabel(DateTime date) {
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  return labels[date.weekday - 1];
}

String shortMonthLabel(DateTime date) {
  const labels = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  return labels[date.month - 1];
}

String shortPlannerDateLabel(DateTime date) {
  return '${shortWeekdayLabel(date)} ${shortMonthLabel(date)} ${date.day}';
}

double drivingPointMiles(List<DrivingPoint> drivingPoints) {
  final groupedPoints = <String, List<LatLng>>{};

  for (final drivingPoint in drivingPoints) {
    groupedPoints
        .putIfAbsent(drivingPointRouteKey(drivingPoint), () => [])
        .add(drivingPoint.point);
  }

  return groupedPoints.values.fold<double>(
    0,
    (totalMiles, points) => totalMiles + routeMiles(points),
  );
}

List<List<LatLng>> drivingPointRouteSegments(List<DrivingPoint> drivingPoints) {
  final groupedPoints = <String, List<LatLng>>{};

  for (final drivingPoint in drivingPoints) {
    groupedPoints
        .putIfAbsent(drivingPointRouteKey(drivingPoint), () => [])
        .add(drivingPoint.point);
  }

  return groupedPoints.values
      .expand(splitRouteSegments)
      .toList(growable: false);
}

class MarketCoverageApp extends StatefulWidget {
  const MarketCoverageApp({super.key});

  @override
  State<MarketCoverageApp> createState() => _MarketCoverageAppState();
}

class _MarketCoverageAppState extends State<MarketCoverageApp> {
  List<Lead> leads = [];
  bool isLoading = true;
  String? activeAccountId;
  String? accountBootstrapError;
  StreamSubscription<AuthState>? authSubscription;
  StreamSubscription<List<ConnectivityResult>>? connectivitySubscription;

  @override
  void initState() {
    super.initState();
    unawaited(MarketService.initActiveCity());

    // Load account-scoped data only when there's a signed-in user; (re)load on
    // sign-in and clear on sign-out.
    isLoading = supabase.auth.currentSession != null;
    if (supabase.auth.currentSession != null) {
      bootstrapAccountAndLoad();
    }

    refreshPendingLeadsQueueCount();
    connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final status = results.map((result) => result.name).join(',');
      unawaited(FieldTestLogger.log('connectivity_change', detail: status));
      final hasConnection = results.any(
        (result) => result != ConnectivityResult.none,
      );
      if (hasConnection) {
        flushPendingLeadsQueue().then((_) {
          if (mounted) loadLeads();
        });
      }
    });

    authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
          if (supabase.auth.currentSession != null) {
            bootstrapAccountAndLoad();
          }
        case AuthChangeEvent.signedOut:
          if (mounted) {
            setState(() {
              leads = [];
              activeAccountId = null;
              accountBootstrapError = null;
              isLoading = false;
            });
          }
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> loadLeads() async {
    final accountId = activeAccountId;
    if (accountId == null) return;

    final data = await supabase
        .from('leads')
        .select()
        .eq('account_id', accountId)
        .order('created_at', ascending: false);

    if (!mounted) return;

    setState(() {
      leads = dedupeLeadsForDisplay(
        data.map<Lead>((item) => Lead.fromMap(item)),
      );
      isLoading = false;
    });
  }

  Future<void> bootstrapAccountAndLoad() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        accountBootstrapError = null;
      });
    }

    try {
      final accountId = await ensureActiveAccount();

      if (!mounted) return;

      setState(() {
        activeAccountId = accountId;
      });

      await loadLeads();
      await flushPendingLeadsQueue();
      await loadLeads();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        leads = [];
        activeAccountId = null;
        accountBootstrapError =
            'Could not load your account. Make sure the account SQL has been run in Supabase.';
        isLoading = false;
      });
    }
  }

  Future<String> ensureActiveAccount() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw StateError('No signed-in user.');
    }

    final memberships = await supabase
        .from('account_members')
        .select('account_id')
        .eq('user_id', user.id)
        .limit(1);

    if (memberships.isNotEmpty) {
      final accountId = memberships.first['account_id']?.toString();
      if (accountId != null && accountId.isNotEmpty) return accountId;
    }

    final account = await supabase
        .from('accounts')
        .insert({'name': 'Personal Account', 'owner_user_id': user.id})
        .select('id')
        .single();
    final accountId = account['id']?.toString();

    if (accountId == null || accountId.isEmpty) {
      throw StateError('Could not create account.');
    }

    await supabase.from('account_members').insert({
      'account_id': accountId,
      'user_id': user.id,
      'role': 'owner',
    });

    return accountId;
  }

  Future<void> addLead(
    String address,
    String condition,
    String notes,
    String source,
    LeadScoreData scoreData,
    double? latitude,
    double? longitude, [
    String? missionId,
  ]) async {
    final accountId = activeAccountId;
    if (accountId == null) return;

    final row = {
      'user_id': supabase.auth.currentUser?.id,
      'account_id': accountId,
      'created_by': supabase.auth.currentUser?.id,
      'address': address,
      'condition': condition,
      'notes': notes,
      'status': 'New Lead',
      'source': source,
      ...scoreData.toMap(),
      'latitude': latitude,
      'longitude': longitude,
    };
    if (missionId != null) row['mission_id'] = missionId;

    final result = await insertLeadWithOfflineQueue(row);
    if (result.savedOnline) {
      await loadLeads();
    }
  }

  Future<void> addParcelLead(
    ParcelProperty parcel,
    LeadScoreData scoreData, [
    String? missionId,
  ]) async {
    final accountId = activeAccountId;
    if (accountId == null) return;

    final leadLocation = parcel.centroid;
    final row = {
      'user_id': supabase.auth.currentUser?.id,
      'account_id': accountId,
      'created_by': supabase.auth.currentUser?.id,
      'address': parcel.displayAddress,
      'condition': 'Parcel Selected',
      'notes': parcel.leadNotes,
      'status': 'New Lead',
      'source': 'Driving For Dollars',
      ...scoreData.toMap(),
      'latitude': leadLocation?.latitude,
      'longitude': leadLocation?.longitude,
      'owner_name': parcel.ownerName ?? '',
      'mailing_address': parcel.mailingAddress ?? '',
      'out_of_state_owner': parcel.outOfStateOwner,
      'assessed_value': parcel.assessedValue,
      'property_type': parcel.propertyType ?? '',
      'lot_size': parcel.lotSizeDisplay,
      'year_built': parcel.yearBuilt,
      'last_sale_date': parcel.saleDate,
      'last_sale_price': parcel.salePrice,
      'deed_type': parcel.deedType,
      'document_date': parcel.documentDate,
      'reception_no': parcel.receptionNo,
      if (parcel.targetScore != null) 'target_score': parcel.targetScore,
    };
    if (missionId != null) row['mission_id'] = missionId;

    final result = await insertLeadWithOfflineQueue(row);
    if (result.savedOnline) {
      await loadLeads();
    }
  }

  Future<void> updateLeadStatus(String leadId, String status) async {
    final normalizedStatus = normalizeLeadStage(status);

    await supabase
        .from('leads')
        .update({'status': normalizedStatus})
        .eq('account_id', activeAccountId ?? '')
        .eq('id', leadId);

    if (!mounted) return;

    setState(() {
      final index = leads.indexWhere((lead) => lead.id == leadId);

      if (index != -1) {
        leads[index] = leads[index].copyWith(status: normalizedStatus);
      }
    });
  }

  Future<void> updateLeadScoreData(
    String leadId,
    LeadScoreData scoreData,
  ) async {
    await supabase
        .from('leads')
        .update(scoreData.toMap())
        .eq('account_id', activeAccountId ?? '')
        .eq('id', leadId);

    if (!mounted) return;

    setState(() {
      final index = leads.indexWhere((lead) => lead.id == leadId);

      if (index != -1) {
        leads[index] = leads[index].copyWith(scoreData: scoreData);
        leads.sort((a, b) => b.score.compareTo(a.score));
      }
    });
  }

  Future<void> updateLeadParcelData(
    String leadId,
    LeadParcelData parcelData,
  ) async {
    await supabase
        .from('leads')
        .update(parcelData.toMap())
        .eq('account_id', activeAccountId ?? '')
        .eq('id', leadId);

    if (!mounted) return;

    setState(() {
      final index = leads.indexWhere((lead) => lead.id == leadId);

      if (index != -1) {
        leads[index] = leads[index].copyWith(parcelData: parcelData);
      }
    });
  }

  Future<void> updateLeadReminderData(
    String leadId,
    LeadReminderData reminderData,
  ) async {
    await supabase
        .from('leads')
        .update(reminderData.toMap())
        .eq('account_id', activeAccountId ?? '')
        .eq('id', leadId);

    if (!mounted) return;

    setState(() {
      final index = leads.indexWhere((lead) => lead.id == leadId);

      if (index != -1) {
        leads[index] = leads[index].copyWith(reminderData: reminderData);
      }
    });
  }

  Future<void> updateLeadOfferData(
    String leadId,
    LeadOfferData offerData,
  ) async {
    await supabase
        .from('leads')
        .update(offerData.toMap())
        .eq('account_id', activeAccountId ?? '')
        .eq('id', leadId);

    if (!mounted) return;

    setState(() {
      final index = leads.indexWhere((lead) => lead.id == leadId);

      if (index != -1) {
        leads[index] = leads[index].copyWith(offerData: offerData);
      }
    });
  }

  Future<void> updateLeadSource(String leadId, String source) async {
    await supabase
        .from('leads')
        .update({'source': source})
        .eq('account_id', activeAccountId ?? '')
        .eq('id', leadId);

    if (!mounted) return;

    setState(() {
      final index = leads.indexWhere((lead) => lead.id == leadId);

      if (index != -1) {
        leads[index] = leads[index].copyWith(source: source);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Market Coverage',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF111827),
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      home: AuthGate(
        signedInBuilder: (context) => MarketCoverageRootScreen(
          leads: leads,
          isLoading: isLoading,
          activeAccountId: activeAccountId,
          accountBootstrapError: accountBootstrapError,
          onAddLead: addLead,
          onAddParcelLead: addParcelLead,
          onUpdateLeadStatus: updateLeadStatus,
          onUpdateLeadSource: updateLeadSource,
          onUpdateLeadScoreData: updateLeadScoreData,
          onUpdateLeadParcelData: updateLeadParcelData,
          onUpdateLeadReminderData: updateLeadReminderData,
          onUpdateLeadOfferData: updateLeadOfferData,
          onRefreshLeads: loadLeads,
        ),
      ),
    );
  }
}

/// Walls the app behind authentication while giving Supabase time to restore a
/// persisted session from browser storage after refresh.
class AuthGate extends StatefulWidget {
  final WidgetBuilder signedInBuilder;

  const AuthGate({super.key, required this.signedInBuilder});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? authSubscription;
  bool isSignedIn = supabase.auth.currentSession != null;
  bool isRestoringSession = true;

  @override
  void initState() {
    super.initState();

    authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      setState(() {
        isSignedIn = (data.session ?? supabase.auth.currentSession) != null;
        isRestoringSession = false;
      });
    });

    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        isSignedIn = supabase.auth.currentSession != null;
        isRestoringSession = false;
      });
    });
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isSignedIn) {
      return widget.signedInBuilder(context);
    }

    if (isRestoringSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return const LoginScreen();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isSignUp = false;
  bool isSubmitting = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email and password.')),
      );
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      if (isSignUp) {
        final response = await supabase.auth.signUp(
          email: email,
          password: password,
        );

        if (!mounted) return;

        if (response.session == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Check your email to confirm your account.'),
            ),
          );
        }
      } else {
        await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } on AuthException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not sign in. Try again.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Market Coverage',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  isSignUp
                      ? 'Create your account'
                      : 'Member login - sign in to continue',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enabled: !isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  enabled: !isSubmitting,
                  onSubmitted: (_) => isSubmitting ? null : submit(),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: isSubmitting ? null : submit,
                    child: Text(
                      isSubmitting
                          ? 'Please wait...'
                          : (isSignUp ? 'Sign Up' : 'Sign In'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => setState(() => isSignUp = !isSignUp),
                  child: Text(
                    isSignUp
                        ? 'Have an account? Sign in'
                        : 'Need an account? Sign up',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MarketCoverageRootScreen extends StatefulWidget {
  final List<Lead> leads;
  final bool isLoading;
  final String? activeAccountId;
  final String? accountBootstrapError;
  final Future<void> Function(
    String address,
    String condition,
    String notes,
    String source,
    LeadScoreData scoreData,
    double? latitude,
    double? longitude, [
    String? missionId,
  ])
  onAddLead;
  final Future<void> Function(
    ParcelProperty parcel,
    LeadScoreData scoreData, [
    String? missionId,
  ])
  onAddParcelLead;
  final Future<void> Function(String leadId, String status) onUpdateLeadStatus;
  final Future<void> Function(String leadId, String source) onUpdateLeadSource;
  final Future<void> Function(String leadId, LeadScoreData scoreData)
  onUpdateLeadScoreData;
  final Future<void> Function(String leadId, LeadParcelData parcelData)
  onUpdateLeadParcelData;
  final Future<void> Function(String leadId, LeadReminderData reminderData)
  onUpdateLeadReminderData;
  final Future<void> Function(String leadId, LeadOfferData offerData)
  onUpdateLeadOfferData;
  final Future<void> Function() onRefreshLeads;

  const MarketCoverageRootScreen({
    super.key,
    required this.leads,
    required this.isLoading,
    required this.activeAccountId,
    required this.accountBootstrapError,
    required this.onAddLead,
    required this.onAddParcelLead,
    required this.onUpdateLeadStatus,
    required this.onUpdateLeadSource,
    required this.onUpdateLeadScoreData,
    required this.onUpdateLeadParcelData,
    required this.onUpdateLeadReminderData,
    required this.onUpdateLeadOfferData,
    required this.onRefreshLeads,
  });

  @override
  State<MarketCoverageRootScreen> createState() =>
      _MarketCoverageRootScreenState();
}

class _MarketCoverageRootScreenState extends State<MarketCoverageRootScreen> {
  final driveScreenKey = GlobalKey<_DrivingScreenState>();
  int selectedTabIndex = 0;

  void openDriveTab() {
    setState(() {
      selectedTabIndex = 0;
    });
  }

  void openAreasTab() {
    setState(() {
      selectedTabIndex = 2;
    });
  }

  void selectTab(int index) {
    if (index == selectedTabIndex) return;

    if (selectedTabIndex == 0 && index != 0) {
      driveScreenKey.currentState?.handleDriveTabHidden();
    }
    if (index == 0) {
      driveScreenKey.currentState?.handleDriveTabVisible();
    }

    setState(() => selectedTabIndex = index);
  }

  void openDrawAreaFlow() {
    openDriveTab();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      driveScreenKey.currentState?.enterDrawAreaMode();
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountId = widget.activeAccountId;

    if (widget.isLoading || accountId == null) {
      return Scaffold(
        body: Center(
          child: widget.accountBootstrapError == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    widget.accountBootstrapError!,
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
      );
    }

    final tabs = [
      DrivingScreen(
        key: driveScreenKey,
        leads: widget.leads,
        activeAccountId: accountId,
        onAddLead: widget.onAddLead,
        onAddParcelLead: widget.onAddParcelLead,
        onUpdateLeadStatus: widget.onUpdateLeadStatus,
        onUpdateLeadSource: widget.onUpdateLeadSource,
        onUpdateLeadScoreData: widget.onUpdateLeadScoreData,
        onUpdateLeadParcelData: widget.onUpdateLeadParcelData,
        onUpdateLeadReminderData: widget.onUpdateLeadReminderData,
        onUpdateLeadOfferData: widget.onUpdateLeadOfferData,
        onRefreshLeads: widget.onRefreshLeads,
        onOpenAreas: openAreasTab,
      ),
      LeadListScreen(
        leads: widget.leads,
        pendingSyncCountListenable: pendingLeadsQueueCountNotifier,
        onUpdateLeadStatus: widget.onUpdateLeadStatus,
        onUpdateLeadSource: widget.onUpdateLeadSource,
        onUpdateLeadScoreData: widget.onUpdateLeadScoreData,
        onUpdateLeadParcelData: widget.onUpdateLeadParcelData,
        onUpdateLeadReminderData: widget.onUpdateLeadReminderData,
        onUpdateLeadOfferData: widget.onUpdateLeadOfferData,
      ),
      _AreasTab(
        driveScreenKey: driveScreenKey,
        onOpenDrive: openDriveTab,
        onCreateNewArea: openDrawAreaFlow,
        onRefresh: () => setState(() {}),
      ),
      const _BusinessTab(),
      _AccountTab(activeAccountId: accountId),
    ];

    return Scaffold(
      body: IndexedStack(index: selectedTabIndex, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedTabIndex,
        type: BottomNavigationBarType.fixed,
        onTap: selectTab,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car),
            label: 'Drive',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Leads'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Areas'),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Business',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

class _AccountTab extends StatelessWidget {
  final String activeAccountId;

  const _AccountTab({required this.activeAccountId});

  Future<void> signOut(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final email = user?.email ?? 'Signed in';

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Session',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(email, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(
                      'Account ID: $activeAccountId',
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign Out / Switch Account'),
                        onPressed: () => signOut(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'After signing out, use Member Login to sign into another account, or tap "Need an account? Sign up" to create a test account.',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreasTab extends StatelessWidget {
  final GlobalKey<_DrivingScreenState> driveScreenKey;
  final VoidCallback onOpenDrive;
  final VoidCallback onCreateNewArea;
  final VoidCallback onRefresh;

  const _AreasTab({
    required this.driveScreenKey,
    required this.onOpenDrive,
    required this.onCreateNewArea,
    required this.onRefresh,
  });

  _DrivingScreenState? get driveState => driveScreenKey.currentState;

  Future<void> openAreaDetail(BuildContext context, DriveArea area) async {
    final state = driveState;
    if (state == null) return;

    await state.setActiveDriveArea(area);
    final center = state.polygonCenter(area.polygon);
    if (center != null) {
      state.focusMapWorkspace(mode: 'targets', point: center, minZoom: 15);
    }
    onRefresh();

    if (!context.mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _AreaDetailScreen(
          driveStateProvider: () => driveState,
          initialArea: area,
          onOpenDrive: onOpenDrive,
        ),
      ),
    );
    onRefresh();
  }

  Future<void> startMissionForArea(BuildContext context, DriveArea area) async {
    final state = driveState;
    if (state == null) return;

    await state.setActiveDriveArea(area);
    onRefresh();
    onOpenDrive();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!state.mounted) return;
      state.openPlanTodayDriveSheet(const <StreetOpportunity>[]);
    });
  }

  Future<void> analyzeArea(DriveArea area) async {
    final state = driveState;
    if (state == null || state.isBuildingMarketMap) return;

    await state.setActiveDriveArea(area);
    onRefresh();
    await state.buildMarketMap();
    onRefresh();
  }

  Future<void> setActive(BuildContext context, DriveArea area) async {
    final state = driveState;
    if (state == null) return;

    await state.setActiveDriveArea(area);
    final center = state.polygonCenter(area.polygon);
    if (center != null) {
      state.focusMapWorkspace(
        mode: 'targets',
        point: center,
        minZoom: 15,
        message: 'Active area set: ${area.name}.',
      );
    }
    onRefresh();
  }

  Future<void> deleteArea(BuildContext context, DriveArea area) async {
    final state = driveState;
    if (state == null) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${area.name}?'),
        content: const Text(
          'This removes the saved area, its market-map properties, and missions for this area.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;

    await state.deleteDriveArea(area);
    onRefresh();
  }

  void openCityDetail(BuildContext context, CityReadiness city) {
    final state = driveState;
    if (state == null) return;

    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _CityDetailScreen(
          city: city,
          activeCity: state.selectedCoverageCity,
          onSetActiveCity: () async {
            await state.changeCoverageCity(city.cityName);
            onRefresh();
          },
        ),
      ),
    );
  }

  void openCityList(BuildContext context) {
    final state = driveState;
    if (state == null) return;

    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _CityListScreen(
          cities: state.cityReadiness,
          activeCity: state.selectedCoverageCity,
          recentMarkets: state.recentMarketCities,
          onOpenCity: (city) => openCityDetail(context, city),
        ),
      ),
    );
  }

  void openMarketDetail(BuildContext context, Market market) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _MarketDetailScreen(
          market: market,
          onActiveMarketChanged: onRefresh,
        ),
      ),
    );
  }

  void openMarketList(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _MarketListScreen(
          onOpenMarket: (market) => openMarketDetail(context, market),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = driveState;
    final areas = state?.driveAreas ?? const <DriveArea>[];
    final activeArea = state?.activeDriveArea;

    return Scaffold(
      appBar: AppBar(title: const Text('Areas')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Create Area'),
                onPressed: onCreateNewArea,
              ),
            ),
            const SizedBox(height: 14),
            _MarketsSection(
              onViewAll: () => openMarketList(context),
              onOpenMarket: (market) => openMarketDetail(context, market),
            ),
            const SizedBox(height: 16),
            if (state == null || state.isLoadingDriveAreas)
              const _AreasLoadingCard()
            else
              _ActiveAreaBanner(
                area: activeArea,
                stats: activeArea == null
                    ? null
                    : _areaStatsForDriveArea(state, activeArea),
                isAnalyzing: state.isBuildingMarketMap,
                onStartMission: activeArea == null
                    ? null
                    : () => startMissionForArea(context, activeArea),
                onAnalyzeArea: activeArea == null
                    ? null
                    : () => analyzeArea(activeArea),
                onOpenArea: activeArea == null
                    ? null
                    : () => openAreaDetail(context, activeArea),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Your Areas',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${areas.length}',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (state == null || state.isLoadingDriveAreas)
              const SizedBox.shrink()
            else if (areas.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'No saved areas yet. Create an area from the map, then analyze it to load homes and start missions.',
                  ),
                ),
              )
            else
              ...areas.map((area) {
                final stats = _areaStatsForDriveArea(state, area);
                final isActive = activeArea?.id == area.id;
                final lastMission = _lastCompletedMissionForArea(state, area);

                return _AreaListCard(
                  area: area,
                  stats: stats,
                  isActive: isActive,
                  lastMissionLabel: lastMissionLabel(lastMission),
                  isAnalyzing: state.isBuildingMarketMap && isActive,
                  onOpenArea: () => openAreaDetail(context, area),
                  onAnalyzeArea: () => analyzeArea(area),
                  onStartMission: () => startMissionForArea(context, area),
                  onSetActive: isActive ? null : () => setActive(context, area),
                  onDelete: () => deleteArea(context, area),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _AreasLoadingCard extends StatelessWidget {
  const _AreasLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading areas...'),
          ],
        ),
      ),
    );
  }
}

class _MarketsSection extends StatelessWidget {
  final VoidCallback onViewAll;
  final ValueChanged<Market> onOpenMarket;

  const _MarketsSection({required this.onViewAll, required this.onOpenMarket});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Market>>(
      future: MarketService.loadAllMarkets(),
      builder: (context, snapshot) {
        final markets = (snapshot.data ?? const <Market>[])
            .where((market) => market.rolloutOrder <= 20)
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Markets',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: onViewAll,
                  label: const Text('Browse all'),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState == ConnectionState.waiting &&
                markets.isEmpty)
              const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snapshot.hasError)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Markets will appear after the markets SQL runs.',
                  ),
                ),
              )
            else
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: markets.length,
                  itemBuilder: (context, index) {
                    final market = markets[index];
                    return _MarketSummaryCard(
                      market: market,
                      onTap: () => onOpenMarket(market),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MarketSummaryCard extends StatelessWidget {
  final Market market;
  final VoidCallback onTap;

  const _MarketSummaryCard({required this.market, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Card(
        margin: const EdgeInsets.only(right: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusDot(color: market.statusColor),
                const SizedBox(height: 10),
                Text(
                  market.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  market.statusLabel,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${market.cachedStreetCount} streets',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketListScreen extends StatefulWidget {
  final ValueChanged<Market> onOpenMarket;

  const _MarketListScreen({required this.onOpenMarket});

  @override
  State<_MarketListScreen> createState() => _MarketListScreenState();
}

class _MarketListScreenState extends State<_MarketListScreen> {
  String query = '';
  String filter = 'All';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Markets')),
      body: SafeArea(
        child: FutureBuilder<List<Market>>(
          future: MarketService.loadAllMarkets(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Markets will appear after the markets SQL runs.',
                  ),
                ),
              );
            }

            final normalizedQuery = query.trim().toLowerCase();
            final markets =
                (snapshot.data ?? const <Market>[])
                    .where((market) {
                      final matchesQuery =
                          normalizedQuery.isEmpty ||
                          market.displayName.toLowerCase().contains(
                            normalizedQuery,
                          ) ||
                          market.state.toLowerCase().contains(
                            normalizedQuery,
                          ) ||
                          market.stateCode.toLowerCase().contains(
                            normalizedQuery,
                          );
                      final matchesFilter =
                          filter == 'All' || market.statusLabel == filter;
                      return matchesQuery && matchesFilter;
                    })
                    .toList(growable: false)
                  ..sort((a, b) {
                    final stateCompare = a.state.compareTo(b.state);
                    if (stateCompare != 0) return stateCompare;
                    return a.rolloutOrder.compareTo(b.rolloutOrder);
                  });
            final states =
                markets.map((market) => market.state).toSet().toList()..sort();

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search markets',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: ['All', 'Ready', 'Partial', 'Planned']
                      .map(
                        (value) => FilterChip(
                          label: Text(value),
                          selected: filter == value,
                          onSelected: (_) => setState(() => filter = value),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 12),
                ...states.expand((state) {
                  final stateMarkets =
                      markets
                          .where((market) => market.state == state)
                          .toList(growable: false)
                        ..sort(
                          (a, b) => a.rolloutOrder.compareTo(b.rolloutOrder),
                        );

                  return [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      color: const Color(0xFFE5E7EB),
                      child: Text(
                        state,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ...stateMarkets.map(
                      (market) => ListTile(
                        leading: _StatusDot(color: market.statusColor),
                        title: Text(market.displayName),
                        subtitle: Text(
                          '${market.statusLabel} - ${market.cachedStreetCount} streets',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => widget.onOpenMarket(market),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ];
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MarketDetailScreen extends StatefulWidget {
  final Market market;
  final VoidCallback onActiveMarketChanged;

  const _MarketDetailScreen({
    required this.market,
    required this.onActiveMarketChanged,
  });

  @override
  State<_MarketDetailScreen> createState() => _MarketDetailScreenState();
}

class _MarketDetailScreenState extends State<_MarketDetailScreen> {
  late final Future<MarketDataHealth> healthFuture;

  @override
  void initState() {
    super.initState();
    healthFuture = MarketService.loadMarketHealth(widget.market);
  }

  @override
  Widget build(BuildContext context) {
    final market = widget.market;

    return Scaffold(
      appBar: AppBar(
        title: Text(market.displayName),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _MarketStatusChip(market: market)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Data Layers',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _MarketDataLayerRow(
                        icon: Icons.timeline,
                        label: 'Street Centerlines',
                        value: market.cachedStreetCount > 0
                            ? '${market.cachedStreetCount} streets'
                            : 'NOT IMPORTED',
                        isReady: market.cachedStreetCount > 0,
                      ),
                      _MarketDataLayerRow(
                        icon: Icons.home_work,
                        label: 'Property Data',
                        value: market.cachedPropertyCount > 0
                            ? '${market.cachedPropertyCount} properties'
                            : 'Not built',
                        isReady: market.cachedPropertyCount > 0,
                      ),
                      _MarketDataLayerRow(
                        icon: Icons.adjust,
                        label: 'Target Scores',
                        value: market.cachedTargetCount > 0
                            ? '${market.cachedTargetCount} targets'
                            : 'Not computed',
                        isReady: market.cachedTargetCount > 0,
                      ),
                      _MarketDataLayerRow(
                        icon: Icons.route,
                        label: 'Coverage Tracking',
                        value: market.cachedStreetCount > 0
                            ? 'Active'
                            : 'Requires street data',
                        isReady: market.cachedStreetCount > 0,
                      ),
                      _MarketDataLayerRow(
                        icon: Icons.map,
                        label: 'Parcel Service',
                        value: market.parcelServiceUrl != null
                            ? 'Configured'
                            : 'Not configured',
                        isReady: market.parcelServiceUrl != null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Live Health Check',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FutureBuilder<MarketDataHealth>(
                        future: healthFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          if (snapshot.hasError || !snapshot.hasData) {
                            return const Text(
                              'Could not load live health check.',
                            );
                          }

                          final health = snapshot.data!;
                          final missingLayers = health.missingLayers;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _MarketHealthRow(
                                label: 'Streets',
                                value: health.streetCount,
                              ),
                              _MarketHealthRow(
                                label: 'Properties',
                                value: health.propertyCount,
                              ),
                              _MarketHealthRow(
                                label: 'Targets',
                                value: health.targetCount,
                              ),
                              _MarketHealthRow(
                                label: 'Leads in market',
                                value: health.leadCount,
                              ),
                              _MarketHealthRow(
                                label: 'Drive Areas',
                                value: health.driveAreaCount,
                              ),
                              _MarketHealthRow(
                                label: 'Missions',
                                value: health.missionCount,
                              ),
                              if (missingLayers.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                const Text(
                                  'Missing Data',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                ...missingLayers.map(
                                  (layer) => Text(
                                    layer,
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Card(
                                color: const Color(0xFFF3F4F6),
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    'Next Step: ${health.primaryNextAction}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (market.isDrivable)
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Set as Active Market'),
                  onPressed: () async {
                    await MarketService.setActiveCity(market.city);
                    widget.onActiveMarketChanged();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Active market set to ${market.displayName}',
                        ),
                      ),
                    );
                    Navigator.pop(context);
                  },
                )
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE5E7EB),
                    foregroundColor: const Color(0xFF6B7280),
                  ),
                  onPressed: null,
                  child: const Text('Data not ready for driving yet'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarketStatusChip extends StatelessWidget {
  final Market market;

  const _MarketStatusChip({required this.market});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: _StatusDot(color: market.statusColor),
      label: Text(market.statusLabel),
    );
  }
}

class _MarketDataLayerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isReady;

  const _MarketDataLayerRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isReady,
  });

  @override
  Widget build(BuildContext context) {
    final color = isReady ? Colors.green : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(isReady ? Icons.check_circle : Icons.cancel, color: color),
          const SizedBox(width: 8),
          Icon(icon, color: const Color(0xFF6B7280), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MarketHealthRow extends StatelessWidget {
  final String label;
  final int value;

  const _MarketHealthRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _ActiveAreaBanner extends StatelessWidget {
  final DriveArea? area;
  final AreaStats? stats;
  final bool isAnalyzing;
  final VoidCallback? onStartMission;
  final VoidCallback? onAnalyzeArea;
  final VoidCallback? onOpenArea;

  const _ActiveAreaBanner({
    required this.area,
    required this.stats,
    required this.isAnalyzing,
    required this.onStartMission,
    required this.onAnalyzeArea,
    required this.onOpenArea,
  });

  @override
  Widget build(BuildContext context) {
    final area = this.area;
    final stats = this.stats;

    if (area == null || stats == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'No active area selected',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Set an area active to analyze homes, start missions, and track coverage from one place.',
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: const Color(0xFF111827),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Active Area',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              area.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${area.city} · '
              '${stats.leadsInArea} leads · ${stats.hotLeads} hot',
              style: const TextStyle(color: Color(0xFFD1D5DB)),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (stats.coveragePercent / 100).clamp(0, 1),
              minHeight: 5,
              color: const Color(0xFF22C55E),
              backgroundColor: const Color(0xFF374151),
            ),
            const SizedBox(height: 12),
            _CoverageStatBlock(
              streetsDriven: stats.streetsCovered,
              totalStreets: stats.streetsCovered + stats.streetsRemaining,
              percent: stats.coveragePercent,
              milesCovered: stats.coveredMiles,
              totalMiles: stats.totalMiles,
              remainingStreets: stats.streetsRemaining,
              dark: true,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.flag),
                  label: const Text('Start Mission'),
                  onPressed: onStartMission,
                ),
                SizedBox(
                  width: 280,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.analytics),
                        label: Text(
                          isAnalyzing
                              ? 'Analyzing...'
                              : motivatedSellersButtonLabel,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF9CA3AF)),
                        ),
                        onPressed: isAnalyzing ? null : onAnalyzeArea,
                      ),
                      const SizedBox(height: 4),
                      const _MotivatedSellersDescription(dark: true),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Area'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF9CA3AF)),
                  ),
                  onPressed: onOpenArea,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaListCard extends StatelessWidget {
  final DriveArea area;
  final AreaStats stats;
  final bool isActive;
  final String lastMissionLabel;
  final bool isAnalyzing;
  final VoidCallback onOpenArea;
  final VoidCallback onAnalyzeArea;
  final VoidCallback onStartMission;
  final VoidCallback? onSetActive;
  final VoidCallback onDelete;

  const _AreaListCard({
    required this.area,
    required this.stats,
    required this.isActive,
    required this.lastMissionLabel,
    required this.isAnalyzing,
    required this.onOpenArea,
    required this.onAnalyzeArea,
    required this.onStartMission,
    required this.onSetActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              area.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 8),
                            const Chip(
                              label: Text('Active'),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        area.city,
                        style: const TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete area',
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: (stats.coveragePercent / 100).clamp(0, 1),
              minHeight: 4,
            ),
            const SizedBox(height: 10),
            _CoverageStatBlock(
              streetsDriven: stats.streetsCovered,
              totalStreets: stats.streetsCovered + stats.streetsRemaining,
              percent: stats.coveragePercent,
              milesCovered: stats.coveredMiles,
              totalMiles: stats.totalMiles,
              remainingStreets: stats.streetsRemaining,
            ),
            const SizedBox(height: 10),
            Text(
              '${stats.leadsInArea} leads · ${stats.hotLeads} hot leads',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Last mission: $lastMissionLabel',
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: onOpenArea,
                  child: const Text('Open Area'),
                ),
                SizedBox(
                  width: 250,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: isAnalyzing ? null : onAnalyzeArea,
                        child: Text(
                          isAnalyzing
                              ? 'Analyzing...'
                              : motivatedSellersButtonLabel,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const _MotivatedSellersDescription(),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: onStartMission,
                  child: const Text('Start Mission'),
                ),
                if (onSetActive != null)
                  TextButton(
                    onPressed: onSetActive,
                    child: const Text('Set Active'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaMetricPill extends StatelessWidget {
  final String label;
  final String value;

  const _AreaMetricPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MotivatedSellersDescription extends StatelessWidget {
  final bool dark;

  const _MotivatedSellersDescription({this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      motivatedSellersDescription,
      style: TextStyle(
        color: dark ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280),
        fontSize: 12,
      ),
    );
  }
}

class _CoverageStatBlock extends StatelessWidget {
  final int streetsDriven;
  final int totalStreets;
  final double percent;
  final double milesCovered;
  final double totalMiles;
  final int remainingStreets;
  final bool dark;

  const _CoverageStatBlock({
    required this.streetsDriven,
    required this.totalStreets,
    required this.percent,
    required this.milesCovered,
    required this.totalMiles,
    required this.remainingStreets,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = dark ? Colors.white : const Color(0xFF111827);
    final mutedColor = dark ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280);

    if (totalStreets == 0) {
      return Text(
        'No street data loaded for this area.',
        style: TextStyle(color: mutedColor),
      );
    }

    final safePercent = percent.clamp(0, 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Streets driven: $streetsDriven of $totalStreets ($safePercent%)',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Miles covered: ${milesCovered.toStringAsFixed(1)} of ${totalMiles.toStringAsFixed(1)} mi',
          style: TextStyle(color: color),
        ),
        const SizedBox(height: 4),
        Text(
          'Remaining: $remainingStreets streets',
          style: TextStyle(color: color),
        ),
      ],
    );
  }
}

class _FirstDriveAreaWelcomeCard extends StatelessWidget {
  final VoidCallback onDrawArea;

  const _FirstDriveAreaWelcomeCard({required this.onDrawArea});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Welcome to Market Coverage OS',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Start by drawing your first Drive Area - tap the button below to outline the neighborhood you want to cover.',
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.edit_location_alt),
                label: const Text('Draw My First Area ->'),
                onPressed: onDrawArea,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FirstMissionTipCard extends StatelessWidget {
  final VoidCallback onDismiss;

  const _FirstMissionTipCard({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onDismiss,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            "Tip: Tap Plan Today's Drive to create your first mission. Streets will turn green as you drive them.",
            style: TextStyle(
              color: Color(0xFF1E3A8A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class MarketsOverviewSection extends StatelessWidget {
  final List<CityReadiness> cities;
  final String activeCity;
  final bool isLoading;
  final VoidCallback onViewAll;
  final ValueChanged<CityReadiness> onOpenCity;

  const MarketsOverviewSection({
    super.key,
    required this.cities,
    required this.activeCity,
    required this.isLoading,
    required this.onViewAll,
    required this.onOpenCity,
  });

  @override
  Widget build(BuildContext context) {
    final activeMarket = cities
        .where((city) => city.cityName == activeCity)
        .firstOrNull;
    final readyCount = cities
        .where((city) => city.statusLabel == 'Ready')
        .length;
    final partialCount = cities
        .where((city) => city.statusLabel == 'Partial')
        .length;
    final plannedCount = cities
        .where((city) => city.statusLabel == 'Planned')
        .length;
    final missingCount = cities
        .where((city) => city.statusLabel == 'Missing Data')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Market Coverage',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(onPressed: onViewAll, child: const Text('View all')),
          ],
        ),
        const SizedBox(height: 8),
        if (isLoading && cities.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Loading market readiness...'),
                ],
              ),
            ),
          )
        else if (cities.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No market city config found yet.'),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activeMarket == null
                    ? 'Active market: $activeCity'
                    : 'Active market: ${activeMarket.displayName}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MarketCountChip(label: 'Ready', count: readyCount),
                  _MarketCountChip(label: 'Partial', count: partialCount),
                  _MarketCountChip(label: 'Planned', count: plannedCount),
                  _MarketCountChip(label: 'Missing Data', count: missingCount),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Planned markets are catalog entries only. They become Partial or Ready only after street/property data exists.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: cities
                      .take(20)
                      .map((city) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: _StatusDot(color: city.statusColor),
                            label: Text(
                              '${city.displayName} · ${city.statusLabel}',
                            ),
                            onPressed: () => onOpenCity(city),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _MarketCountChip extends StatelessWidget {
  final String label;
  final int count;

  const _MarketCountChip({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: $count'));
  }
}

class _CityListScreen extends StatefulWidget {
  final List<CityReadiness> cities;
  final String activeCity;
  final List<String> recentMarkets;
  final ValueChanged<CityReadiness> onOpenCity;

  const _CityListScreen({
    required this.cities,
    required this.activeCity,
    required this.recentMarkets,
    required this.onOpenCity,
  });

  @override
  State<_CityListScreen> createState() => _CityListScreenState();
}

class _CityListScreenState extends State<_CityListScreen> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final filteredCities = widget.cities
        .where((city) {
          if (normalizedQuery.isEmpty) return true;

          return city.cityName.toLowerCase().contains(normalizedQuery) ||
              city.displayName.toLowerCase().contains(normalizedQuery) ||
              city.stateName.toLowerCase().contains(normalizedQuery) ||
              city.stateCode.toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);
    final activeMarket = widget.cities
        .where((city) => city.cityName == widget.activeCity)
        .firstOrNull;
    final recentMarkets = widget.recentMarkets
        .map(
          (cityName) => widget.cities
              .where((city) => city.cityName == cityName)
              .firstOrNull,
        )
        .whereType<CityReadiness>()
        .toList(growable: false);
    final stateCodes =
        filteredCities
            .map(
              (city) =>
                  city.stateCode.isEmpty ? city.stateName : city.stateCode,
            )
            .toSet()
            .toList()
          ..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Market Coverage')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search city or state',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 16),
            if (activeMarket != null) ...[
              const Text(
                'Active Market',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _MarketCard(
                city: activeMarket,
                isActive: true,
                onTap: () => widget.onOpenCity(activeMarket),
              ),
              const SizedBox(height: 12),
            ],
            if (recentMarkets.isNotEmpty) ...[
              const Text(
                'Recent Markets',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recentMarkets
                    .map((city) {
                      return ActionChip(
                        avatar: _StatusDot(color: city.statusColor),
                        label: Text(city.displayName),
                        onPressed: () => widget.onOpenCity(city),
                      );
                    })
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
            ],
            ...stateCodes.expand((stateCode) {
              final stateCities =
                  filteredCities
                      .where(
                        (city) =>
                            (city.stateCode.isEmpty
                                ? city.stateName
                                : city.stateCode) ==
                            stateCode,
                      )
                      .toList(growable: false)
                    ..sort((a, b) {
                      final rankCompare = (a.rankInState ?? 999).compareTo(
                        b.rankInState ?? 999,
                      );
                      if (rankCompare != 0) return rankCompare;
                      return a.cityName.compareTo(b.cityName);
                    });

              return [
                Text(
                  stateCode,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...stateCities.map(
                  (city) => _MarketCard(
                    city: city,
                    isActive: city.cityName == widget.activeCity,
                    onTap: () => widget.onOpenCity(city),
                  ),
                ),
                const SizedBox(height: 12),
              ];
            }),
          ],
        ),
      ),
    );
  }
}

class _MarketCard extends StatelessWidget {
  final CityReadiness city;
  final bool isActive;
  final VoidCallback onTap;

  const _MarketCard({
    required this.city,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: _StatusDot(color: city.statusColor),
        title: Row(
          children: [
            Expanded(child: Text(city.displayName)),
            _ReadinessChip(city: city),
          ],
        ),
        subtitle: Text(
          '${city.streetCount} streets - ${city.propertyCount} properties - ${city.targetCount} targets\n'
          '${city.leadCount} leads - ${city.driveAreaCount} areas - ${city.suggestedNextStep}'
          '${isActive ? ' - Active market' : ''}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _MarketPickerScreen extends StatefulWidget {
  final List<CityReadiness> cities;
  final String activeCity;
  final List<String> recentMarkets;

  const _MarketPickerScreen({
    required this.cities,
    required this.activeCity,
    required this.recentMarkets,
  });

  @override
  State<_MarketPickerScreen> createState() => _MarketPickerScreenState();
}

class _MarketPickerScreenState extends State<_MarketPickerScreen> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final filteredCities = widget.cities
        .where((city) {
          if (normalizedQuery.isEmpty) return true;

          return city.cityName.toLowerCase().contains(normalizedQuery) ||
              city.displayName.toLowerCase().contains(normalizedQuery) ||
              city.stateName.toLowerCase().contains(normalizedQuery) ||
              city.stateCode.toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);
    final activeMarket = widget.cities
        .where((city) => city.cityName == widget.activeCity)
        .firstOrNull;
    final recentMarkets = widget.recentMarkets
        .map(
          (cityName) => widget.cities
              .where((city) => city.cityName == cityName)
              .firstOrNull,
        )
        .whereType<CityReadiness>()
        .toList(growable: false);
    final stateCodes =
        filteredCities
            .map(
              (city) =>
                  city.stateCode.isEmpty ? city.stateName : city.stateCode,
            )
            .toSet()
            .toList()
          ..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Choose Market')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search city or state',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 16),
            if (activeMarket != null) ...[
              const Text(
                'Active Market',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _MarketCard(
                city: activeMarket,
                isActive: true,
                onTap: () => Navigator.pop(context, activeMarket),
              ),
              const SizedBox(height: 12),
            ],
            if (recentMarkets.isNotEmpty) ...[
              const Text(
                'Recent Markets',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recentMarkets
                    .map((city) {
                      return ActionChip(
                        avatar: _StatusDot(color: city.statusColor),
                        label: Text(city.displayName),
                        onPressed: () => Navigator.pop(context, city),
                      );
                    })
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
            ],
            ...stateCodes.expand((stateCode) {
              final stateCities =
                  filteredCities
                      .where(
                        (city) =>
                            (city.stateCode.isEmpty
                                ? city.stateName
                                : city.stateCode) ==
                            stateCode,
                      )
                      .toList(growable: false)
                    ..sort((a, b) {
                      final rankCompare = (a.rankInState ?? 999).compareTo(
                        b.rankInState ?? 999,
                      );
                      if (rankCompare != 0) return rankCompare;
                      return a.cityName.compareTo(b.cityName);
                    });

              return [
                Text(
                  stateCode,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...stateCities.map(
                  (city) => _MarketCard(
                    city: city,
                    isActive: city.cityName == widget.activeCity,
                    onTap: () => Navigator.pop(context, city),
                  ),
                ),
                const SizedBox(height: 12),
              ];
            }),
          ],
        ),
      ),
    );
  }
}

class _ReadinessChip extends StatelessWidget {
  final CityReadiness city;

  const _ReadinessChip({required this.city});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: _StatusDot(color: city.statusColor),
      label: Text(city.statusLabel),
    );
  }
}

class _CityDetailScreen extends StatelessWidget {
  final CityReadiness city;
  final String activeCity;
  final Future<void> Function() onSetActiveCity;

  const _CityDetailScreen({
    required this.city,
    required this.activeCity,
    required this.onSetActiveCity,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(city.displayName)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      city.readinessScore.toStringAsFixed(0),
                      style: TextStyle(
                        color: city.statusColor,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      city.statusLabel,
                      style: TextStyle(
                        color: city.statusColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      city.cityName == activeCity
                          ? 'Active coverage city'
                          : 'Market status: ${city.marketStatus}',
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _AreaMetricPill(
                          label: 'Next step',
                          value: city.suggestedNextStep,
                        ),
                        _AreaMetricPill(
                          label: 'Drive areas',
                          value: city.driveAreaCount.toString(),
                        ),
                        _AreaMetricPill(
                          label: 'Leads',
                          value: city.leadCount.toString(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Data Layers',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _DataLayerRow(
                      status: city.streetCount >= 500
                          ? _LayerStatus.ready
                          : city.streetCount > 0
                          ? _LayerStatus.partial
                          : _LayerStatus.missing,
                      label: 'Street centerlines',
                      detail: '${city.streetCount} streets',
                    ),
                    _DataLayerRow(
                      status: city.parcelServiceVerified
                          ? _LayerStatus.ready
                          : _LayerStatus.missing,
                      label: 'Parcel service',
                      detail: city.parcelServiceVerified
                          ? 'Verified'
                          : 'NOT VERIFIED',
                    ),
                    _DataLayerRow(
                      status: city.marketMapBuilt
                          ? _LayerStatus.ready
                          : _LayerStatus.missing,
                      label: 'Market map',
                      detail: city.marketMapBuilt
                          ? '${city.propertyCount} properties, ${city.targetCount} targets'
                          : 'NOT BUILT',
                    ),
                    _DataLayerRow(
                      status: city.ownerInfoPercent >= 80
                          ? _LayerStatus.ready
                          : city.ownerInfoPercent > 0
                          ? _LayerStatus.partial
                          : _LayerStatus.missing,
                      label: 'Owner info',
                      detail:
                          '${city.ownerInfoPercent.toStringAsFixed(0)}% filled',
                    ),
                    _DataLayerRow(
                      status: city.coveredStreetCount > 0
                          ? _LayerStatus.ready
                          : city.streetCount > 0
                          ? _LayerStatus.partial
                          : _LayerStatus.missing,
                      label: 'Coverage tracking',
                      detail: '${city.coveredStreetCount} covered streets',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Driving Readiness',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _CapabilityRow(label: 'Missions', enabled: city.isDrivable),
                    _CapabilityRow(
                      label: 'Property Preview',
                      enabled: city.parcelServiceVerified,
                    ),
                    _CapabilityRow(
                      label: 'Quick Capture',
                      enabled: city.streetCount > 0,
                    ),
                    _CapabilityRow(
                      label: 'Market Map targets',
                      enabled: city.marketMapBuilt,
                    ),
                    _CapabilityRow(
                      label: 'Coverage tracking',
                      enabled: city.streetCount > 0,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (city.statusLabel != 'Ready')
              Card(
                color: const Color(0xFFF3F4F6),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${city.displayName} is ${city.statusLabel}. You can set it active, but Drive will show missing streets/properties until data is imported.',
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.check_circle),
              label: Text(
                city.cityName == activeCity
                    ? 'Active City'
                    : 'Set as Active City',
              ),
              onPressed: city.cityName == activeCity
                  ? null
                  : () async {
                      await onSetActiveCity();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Active city set to ${city.displayName}',
                          ),
                        ),
                      );
                      Navigator.pop(context);
                    },
            ),
          ],
        ),
      ),
    );
  }
}

enum _LayerStatus { ready, partial, missing }

class _DataLayerRow extends StatelessWidget {
  final _LayerStatus status;
  final String label;
  final String detail;

  const _DataLayerRow({
    required this.status,
    required this.label,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      _LayerStatus.ready => Icons.check_circle,
      _LayerStatus.partial => Icons.remove_circle,
      _LayerStatus.missing => Icons.cancel,
    };
    final color = switch (status) {
      _LayerStatus.ready => Colors.green,
      _LayerStatus.partial => Colors.amber,
      _LayerStatus.missing => Colors.red,
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(label),
      subtitle: Text(detail),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  final String label;
  final bool enabled;

  const _CapabilityRow({required this.label, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        enabled ? Icons.check_circle : Icons.cancel,
        color: enabled ? Colors.green : Colors.grey,
      ),
      title: Text(label),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;

  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

AreaStats _areaStatsForDriveArea(
  _DrivingScreenState driveState,
  DriveArea area,
) {
  final streets = driveState.streetsInsideArea(area);
  final properties = _marketPropertiesForArea(driveState, area);

  return computeAreaStats(
    polygon: area.polygon,
    streets: streets
        .map((street) => AreaStatsStreet(id: street.id, path: street.path))
        .toList(growable: false),
    coveredStreetIds: driveState.coveredStreetIds,
    leads: driveState.drivingLeads
        .map(
          (lead) => AreaStatsLead(
            point: lead.latitude == null || lead.longitude == null
                ? null
                : LatLng(lead.latitude!, lead.longitude!),
            score: lead.score,
          ),
        )
        .toList(growable: false),
    targetCount: properties.where(_isTargetMarketProperty).length,
  );
}

List<MarketProperty> _marketPropertiesForArea(
  _DrivingScreenState driveState,
  DriveArea area,
) {
  return driveState.marketProperties
      .where((property) => property.driveAreaId == area.id)
      .toList(growable: false);
}

bool _isTargetMarketProperty(MarketProperty property) {
  return property.targetScore > 0 ||
      property.outOfState ||
      property.absentee ||
      property.portfolioCount >= 3 ||
      property.lowImprovementRatio ||
      _marketPropertySignal(property, 'long_held') ||
      _marketPropertySignal(property, 'older_build');
}

bool _marketPropertySignal(MarketProperty property, String key) {
  final value = property.signals[key];
  if (value is bool) return value;
  if (value is num) return value != 0;

  return value?.toString().toLowerCase() == 'true';
}

bool _hasMarketPropertySignal(Iterable<MarketProperty> properties, String key) {
  return properties.any((property) => property.signals.containsKey(key));
}

Mission? _lastCompletedMissionForArea(
  _DrivingScreenState driveState,
  DriveArea area,
) {
  return driveState.completedMissions
      .where((mission) => mission.driveAreaId == area.id)
      .firstOrNull;
}

String lastMissionLabel(Mission? mission) {
  final completedAt = mission?.completedAt?.toLocal();
  if (completedAt == null) return 'No missions yet';

  final now = DateTime.now();
  final days = now.difference(completedAt).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';

  return '$days days ago';
}

String _missionDateLabel(DateTime? date) {
  final local = date?.toLocal();
  if (local == null) return 'Completed mission';

  return '${local.month}/${local.day}/${local.year}';
}

class _AreaDetailScreen extends StatefulWidget {
  final _DrivingScreenState? Function() driveStateProvider;
  final DriveArea initialArea;
  final VoidCallback onOpenDrive;

  const _AreaDetailScreen({
    required this.driveStateProvider,
    required this.initialArea,
    required this.onOpenDrive,
  });

  @override
  State<_AreaDetailScreen> createState() => _AreaDetailScreenState();
}

class _AreaDetailScreenState extends State<_AreaDetailScreen> {
  bool targetsOnly = false;
  bool filterOutOfState = false;
  bool filterAbsentee = false;
  bool filterPortfolio = false;
  bool filterLowImprovement = false;
  bool filterLongHeld = false;
  bool filterOlderBuild = false;

  _DrivingScreenState? get driveStateOrNull {
    final state = widget.driveStateProvider();
    if (state == null || !state.mounted) return null;

    return state;
  }

  DriveArea get area {
    final state = driveStateOrNull;

    return state?.driveAreas
            .where((item) => item.id == widget.initialArea.id)
            .firstOrNull ??
        widget.initialArea;
  }

  Future<void> startMission() async {
    final state = driveStateOrNull;
    if (state == null) return;

    await state.setActiveDriveArea(area);
    if (!mounted) return;

    widget.onOpenDrive();
    Navigator.pop(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentState = driveStateOrNull;
      if (currentState == null) return;
      currentState.openPlanTodayDriveSheet(const <StreetOpportunity>[]);
    });
  }

  Future<void> analyzeArea() async {
    final state = driveStateOrNull;
    if (state == null) return;

    await state.setActiveDriveArea(area);
    await state.buildMarketMap();
    if (mounted) setState(() {});
  }

  Future<void> markComplete() async {
    final state = driveStateOrNull;
    if (state == null) return;

    await state.setActiveDriveArea(area);
    await state.markActiveDriveAreaComplete();
    if (mounted) setState(() {});
  }

  List<MarketProperty> filteredProperties(List<MarketProperty> properties) {
    final filtered = properties
        .where((property) {
          if (targetsOnly && !_isTargetMarketProperty(property)) return false;
          if (filterOutOfState && !property.outOfState) return false;
          if (filterAbsentee && !property.absentee) return false;
          if (filterPortfolio && property.portfolioCount < 3) return false;
          if (filterLowImprovement && !property.lowImprovementRatio) {
            return false;
          }
          if (filterLongHeld && !_marketPropertySignal(property, 'long_held')) {
            return false;
          }
          if (filterOlderBuild &&
              !_marketPropertySignal(property, 'older_build')) {
            return false;
          }

          return true;
        })
        .toList(growable: false);

    filtered.sort((a, b) => b.targetScore.compareTo(a.targetScore));
    return filtered;
  }

  Widget signalChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final driveState = driveStateOrNull;
    if (driveState == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.initialArea.name)),
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Drive data is reloading. Go back and open this area again.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final activeArea = driveState.activeDriveArea;
    final isActive = activeArea?.id == area.id;
    final stats = _areaStatsForDriveArea(driveState, area);
    final streets = driveState.streetsInsideArea(area);
    final uncoveredStreets = streets
        .where((street) => !driveState.coveredStreetIds.contains(street.id))
        .toList(growable: false);
    final properties = _marketPropertiesForArea(driveState, area);
    final targetCount = properties.where(_isTargetMarketProperty).length;
    final opportunityScore =
        driveState.driveAreaRemainingOpportunity[area.id] ??
        driveState
            .streetOpportunitiesFor(streets, properties)
            .fold<double>(0, (total, item) => total + item.score);
    final shownProperties = filteredProperties(properties);
    final hasLongHeld = _hasMarketPropertySignal(properties, 'long_held');
    final hasOlderBuild = _hasMarketPropertySignal(properties, 'older_build');
    final completedMissions = driveState.completedMissions
        .where((mission) => mission.driveAreaId == area.id)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(area.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            area.name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            area.city,
                            style: const TextStyle(color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Switch(
                          value: isActive,
                          onChanged: (value) async {
                            await driveState.setActiveDriveArea(
                              value ? area : null,
                            );
                            if (mounted) setState(() {});
                          },
                        ),
                        Text(isActive ? 'Active' : 'Inactive'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Coverage',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: (stats.coveragePercent / 100).clamp(0, 1),
                      minHeight: 7,
                    ),
                    const SizedBox(height: 12),
                    _CoverageStatBlock(
                      streetsDriven: stats.streetsCovered,
                      totalStreets:
                          stats.streetsCovered + stats.streetsRemaining,
                      percent: stats.coveragePercent,
                      milesCovered: stats.coveredMiles,
                      totalMiles: stats.totalMiles,
                      remainingStreets: stats.streetsRemaining,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pipeline',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _DriveStatTile(
                          label: 'Leads',
                          value: stats.leadsInArea.toString(),
                          icon: Icons.person_pin_circle,
                          color: const Color(0xFFDC2626),
                        ),
                        _DriveStatTile(
                          label: 'Hot leads',
                          value: stats.hotLeads.toString(),
                          icon: Icons.local_fire_department,
                          color: const Color(0xFFF97316),
                        ),
                        _DriveStatTile(
                          label: 'Targets',
                          value: targetCount.toString(),
                          icon: Icons.adjust,
                          color: const Color(0xFF7C3AED),
                        ),
                        _DriveStatTile(
                          label: 'Opp score',
                          value: opportunityScore.toStringAsFixed(0),
                          icon: Icons.bolt,
                          color: const Color(0xFF2563EB),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Targets',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          '${shownProperties.length} of ${properties.length} homes',
                          style: const TextStyle(color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('All homes')),
                        ButtonSegment(value: true, label: Text('Targets only')),
                      ],
                      selected: {targetsOnly},
                      onSelectionChanged: (selection) {
                        setState(() => targetsOnly = selection.first);
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        signalChip(
                          label: 'Out of state',
                          selected: filterOutOfState,
                          onSelected: (value) =>
                              setState(() => filterOutOfState = value),
                        ),
                        signalChip(
                          label: 'Absentee',
                          selected: filterAbsentee,
                          onSelected: (value) =>
                              setState(() => filterAbsentee = value),
                        ),
                        signalChip(
                          label: 'Portfolio 3+',
                          selected: filterPortfolio,
                          onSelected: (value) =>
                              setState(() => filterPortfolio = value),
                        ),
                        signalChip(
                          label: 'Low improvement',
                          selected: filterLowImprovement,
                          onSelected: (value) =>
                              setState(() => filterLowImprovement = value),
                        ),
                        if (hasLongHeld)
                          signalChip(
                            label: 'Long held',
                            selected: filterLongHeld,
                            onSelected: (value) =>
                                setState(() => filterLongHeld = value),
                          ),
                        if (hasOlderBuild)
                          signalChip(
                            label: 'Older build',
                            selected: filterOlderBuild,
                            onSelected: (value) =>
                                setState(() => filterOlderBuild = value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (driveState.isLoadingMarketProperties)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (properties.isEmpty)
                      const Text(motivatedSellersDescription)
                    else if (shownProperties.isEmpty)
                      const Text('No homes match these filters.')
                    else
                      ...shownProperties.take(50).map((property) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            property.parcel.displayAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _targetSignalSummary(property),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: driveState.targetScoreBadge(
                            property.targetScore,
                            onTap: () =>
                                driveState.showTargetScoreBreakdown(property),
                          ),
                          onTap: () =>
                              driveState.openParcelPreview(property.parcel),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Missions',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (completedMissions.isEmpty)
                      const Text('No completed missions yet.')
                    else
                      ...completedMissions.map((mission) {
                        final leads = driveState.leadsForMission(mission);
                        final miles = driveState.milesForMission(mission);
                        final covered = driveState.coveredStreetCountForMission(
                          mission,
                        );

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_missionDateLabel(mission.completedAt)),
                          subtitle: Text(
                            '$covered streets · ${leads.length} leads · '
                            '${miles.toStringAsFixed(2)} mi',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => driveState.openMissionResults(
                            mission: mission,
                            areaName: area.name,
                            leads: leads,
                            streetsCovered: covered,
                            opportunityCaptured:
                                mission.opportunityCaptured ?? 0,
                            milesDriven: miles,
                            actualMinutes: mission.actualMinutes,
                            areaRemainingEstimatedMinutes: driveState
                                .estimatedMinutesForStreets(uncoveredStreets),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.flag),
                      label: const Text('Start Mission'),
                      onPressed: startMission,
                    ),
                    const SizedBox(height: 8),
                    if (properties.isEmpty)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.analytics),
                        label: Text(
                          driveState.isBuildingMarketMap
                              ? 'Analyzing area...'
                              : motivatedSellersButtonLabel,
                        ),
                        onPressed: driveState.isBuildingMarketMap
                            ? null
                            : analyzeArea,
                      )
                    else
                      TextButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          driveState.isBuildingMarketMap
                              ? 'Analyzing area...'
                              : motivatedSellersButtonLabel,
                        ),
                        onPressed: driveState.isBuildingMarketMap
                            ? null
                            : analyzeArea,
                      ),
                    const SizedBox(height: 4),
                    const _MotivatedSellersDescription(),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: markComplete,
                      child: const Text('Mark Complete'),
                    ),
                    if (driveState.marketMapMessage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        driveState.marketMapMessage,
                        style: const TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _targetSignalSummary(MarketProperty property) {
  final signals = <String>[
    if (property.outOfState) 'out of state',
    if (property.absentee) 'absentee',
    if (property.portfolioCount >= 3) 'portfolio ${property.portfolioCount}',
    if (property.lowImprovementRatio) 'low improvement',
    if (_marketPropertySignal(property, 'long_held')) 'long held',
    if (_marketPropertySignal(property, 'older_build')) 'older build',
  ];

  final owner = property.parcel.ownerName;
  final ownerLabel = owner == null || owner.trim().isEmpty
      ? null
      : owner.trim();

  final rows = <String>[];
  if (ownerLabel != null) rows.add(ownerLabel);
  if (signals.isNotEmpty) rows.add(signals.join(', '));
  return rows.join(' - ');
}

class _BusinessTab extends StatelessWidget {
  const _BusinessTab();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart, size: 64, color: Color(0xFF6B7280)),
            SizedBox(height: 16),
            Text(
              'Business dashboard coming soon',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  final List<Lead> leads;
  final bool isLoading;
  final String? activeAccountId;
  final String? accountBootstrapError;
  final Future<void> Function(
    String address,
    String condition,
    String notes,
    String source,
    LeadScoreData scoreData,
    double? latitude,
    double? longitude, [
    String? missionId,
  ])
  onAddLead;
  final Future<void> Function(
    ParcelProperty parcel,
    LeadScoreData scoreData, [
    String? missionId,
  ])
  onAddParcelLead;
  final Future<void> Function(String leadId, String status) onUpdateLeadStatus;
  final Future<void> Function(String leadId, String source) onUpdateLeadSource;
  final Future<void> Function(String leadId, LeadScoreData scoreData)
  onUpdateLeadScoreData;
  final Future<void> Function(String leadId, LeadParcelData parcelData)
  onUpdateLeadParcelData;
  final Future<void> Function(String leadId, LeadReminderData reminderData)
  onUpdateLeadReminderData;
  final Future<void> Function(String leadId, LeadOfferData offerData)
  onUpdateLeadOfferData;

  const DashboardScreen({
    super.key,
    required this.leads,
    required this.isLoading,
    required this.activeAccountId,
    required this.accountBootstrapError,
    required this.onAddLead,
    required this.onAddParcelLead,
    required this.onUpdateLeadStatus,
    required this.onUpdateLeadSource,
    required this.onUpdateLeadScoreData,
    required this.onUpdateLeadParcelData,
    required this.onUpdateLeadReminderData,
    required this.onUpdateLeadOfferData,
  });

  @override
  Widget build(BuildContext context) {
    final today = todayDateOnly();
    final weekStart = startOfCurrentWeek();
    final leadsNeedingRevisitToday = leads.where((lead) {
      return lead.reminderData.followUpStatus != 'Completed' &&
          isSameDate(lead.reminderData.reminderDate, today);
    }).length;
    final overdueRevisits = leads.where((lead) {
      return lead.reminderData.followUpStatus != 'Completed' &&
          isBeforeDate(lead.reminderData.reminderDate, today);
    }).length;
    final newLeadsThisWeek = leads.where((lead) {
      final createdAt = lead.createdAt?.toLocal();

      if (createdAt == null) return false;

      return !createdAt.isBefore(weekStart);
    }).length;
    final hotLeads = leads.where((lead) => lead.score >= 70).length;
    final averageScore = leads.isEmpty
        ? 0
        : leads.fold<int>(0, (total, lead) => total + lead.score) /
              leads.length;
    final pipelineLeads = leads
        .where((lead) => normalizeLeadStage(lead.status) != 'New Lead')
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Market Coverage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : accountBootstrapError != null || activeAccountId == null
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          accountBootstrapError ??
                              'Preparing your account. Refresh if this takes more than a few seconds.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Today\'s command center',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Drive smarter, follow up faster, and keep every opportunity moving.',
                              style: TextStyle(
                                color: Color(0xFFD1D5DB),
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => DrivingScreen(
                                          leads: leads,
                                          activeAccountId: activeAccountId!,
                                          onAddLead: onAddLead,
                                          onAddParcelLead: onAddParcelLead,
                                          onUpdateLeadStatus:
                                              onUpdateLeadStatus,
                                          onUpdateLeadSource:
                                              onUpdateLeadSource,
                                          onUpdateLeadScoreData:
                                              onUpdateLeadScoreData,
                                          onUpdateLeadParcelData:
                                              onUpdateLeadParcelData,
                                          onUpdateLeadReminderData:
                                              onUpdateLeadReminderData,
                                          onUpdateLeadOfferData:
                                              onUpdateLeadOfferData,
                                          onRefreshLeads: () async {},
                                          onOpenAreas: () {},
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.near_me),
                                  label: const Text('Start Driving'),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Color(0xFF4B5563),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            AddLeadScreen(onAddLead: onAddLead),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.add_home_work),
                                  label: const Text('Add Lead'),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Color(0xFF4B5563),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => LeadListScreen(
                                          leads: leads,
                                          pendingSyncCountListenable:
                                              pendingLeadsQueueCountNotifier,
                                          onUpdateLeadStatus:
                                              onUpdateLeadStatus,
                                          onUpdateLeadSource:
                                              onUpdateLeadSource,
                                          onUpdateLeadScoreData:
                                              onUpdateLeadScoreData,
                                          onUpdateLeadParcelData:
                                              onUpdateLeadParcelData,
                                          onUpdateLeadReminderData:
                                              onUpdateLeadReminderData,
                                          onUpdateLeadOfferData:
                                              onUpdateLeadOfferData,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.view_list),
                                  label: const Text('View Leads'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth > 900 ? 4 : 2;
                        final cardWidth =
                            (constraints.maxWidth - ((columns - 1) * 12)) /
                            columns;

                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: cardWidth,
                              child: _DashboardMetricCard(
                                label: 'Total leads',
                                value: leads.length.toString(),
                                icon: Icons.home_work,
                                color: const Color(0xFF2563EB),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _DashboardMetricCard(
                                label: 'Hot leads',
                                value: hotLeads.toString(),
                                icon: Icons.local_fire_department,
                                color: const Color(0xFFDC2626),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _DashboardMetricCard(
                                label: 'Avg score',
                                value: averageScore.toStringAsFixed(0),
                                icon: Icons.speed,
                                color: const Color(0xFFF59E0B),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _DashboardMetricCard(
                                label: 'In pipeline',
                                value: pipelineLeads.toString(),
                                icon: Icons.account_tree,
                                color: const Color(0xFF059669),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Follow-up queue',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _DashboardQueueRow(
                                    label: 'Due today',
                                    value: leadsNeedingRevisitToday,
                                    color: const Color(0xFF2563EB),
                                  ),
                                  _DashboardQueueRow(
                                    label: 'Overdue',
                                    value: overdueRevisits,
                                    color: const Color(0xFFDC2626),
                                  ),
                                  _DashboardQueueRow(
                                    label: 'New this week',
                                    value: newLeadsThisWeek,
                                    color: const Color(0xFF059669),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Best next move',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    overdueRevisits > 0
                                        ? 'Clear overdue follow-ups before adding more cold leads.'
                                        : leads.isEmpty
                                        ? 'Start Driving to build your first route-backed lead list.'
                                        : 'Open Driving Mode and keep building coverage in your active area.',
                                    style: const TextStyle(
                                      color: Color(0xFF4B5563),
                                      fontSize: 15,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => DrivingScreen(
                                              leads: leads,
                                              activeAccountId: activeAccountId!,
                                              onAddLead: onAddLead,
                                              onAddParcelLead: onAddParcelLead,
                                              onUpdateLeadStatus:
                                                  onUpdateLeadStatus,
                                              onUpdateLeadSource:
                                                  onUpdateLeadSource,
                                              onUpdateLeadScoreData:
                                                  onUpdateLeadScoreData,
                                              onUpdateLeadParcelData:
                                                  onUpdateLeadParcelData,
                                              onUpdateLeadReminderData:
                                                  onUpdateLeadReminderData,
                                              onUpdateLeadOfferData:
                                                  onUpdateLeadOfferData,
                                              onRefreshLeads: () async {},
                                              onOpenAreas: () {},
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.arrow_forward),
                                      label: const Text('Open Driving Mode'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 16),
                      _DebugAccountStatusCard(
                        activeAccountId: activeAccountId,
                        accountBootstrapError: accountBootstrapError,
                        isLoading: isLoading,
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _DebugAccountStatusCard extends StatelessWidget {
  final String? activeAccountId;
  final String? accountBootstrapError;
  final bool isLoading;

  const _DebugAccountStatusCard({
    required this.activeAccountId,
    required this.accountBootstrapError,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final isReady =
        !isLoading && activeAccountId != null && accountBootstrapError == null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isReady ? Icons.verified_user : Icons.warning_amber,
                  color: isReady
                      ? const Color(0xFF059669)
                      : const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Debug account status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DebugAccountRow(
              label: 'Account ready',
              value: isReady ? 'Yes' : 'No',
            ),
            _DebugAccountRow(
              label: 'activeAccountId',
              value: activeAccountId ?? 'Not loaded',
            ),
            _DebugAccountRow(
              label: 'User email',
              value: user?.email ?? 'Not signed in',
            ),
            if (accountBootstrapError != null)
              _DebugAccountRow(
                label: 'Bootstrap error',
                value: accountBootstrapError!,
              ),
          ],
        ),
      ),
    );
  }
}

class _DebugAccountRow extends StatelessWidget {
  final String label;
  final String value;

  const _DebugAccountRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: Color(0xFF111827)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _DashboardMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardQueueRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _DashboardQueueRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class DrivingScreen extends StatefulWidget {
  final List<Lead> leads;
  final String activeAccountId;

  final Future<void> Function(
    String address,
    String condition,
    String notes,
    String source,
    LeadScoreData scoreData,
    double? latitude,
    double? longitude, [
    String? missionId,
  ])
  onAddLead;
  final Future<void> Function(
    ParcelProperty parcel,
    LeadScoreData scoreData, [
    String? missionId,
  ])
  onAddParcelLead;
  final Future<void> Function(String leadId, String status) onUpdateLeadStatus;
  final Future<void> Function(String leadId, String source) onUpdateLeadSource;
  final Future<void> Function(String leadId, LeadScoreData scoreData)
  onUpdateLeadScoreData;
  final Future<void> Function(String leadId, LeadParcelData parcelData)
  onUpdateLeadParcelData;
  final Future<void> Function(String leadId, LeadReminderData reminderData)
  onUpdateLeadReminderData;
  final Future<void> Function(String leadId, LeadOfferData offerData)
  onUpdateLeadOfferData;
  final Future<void> Function() onRefreshLeads;
  final VoidCallback onOpenAreas;

  const DrivingScreen({
    super.key,
    required this.leads,
    required this.activeAccountId,
    required this.onAddLead,
    required this.onAddParcelLead,
    required this.onUpdateLeadStatus,
    required this.onUpdateLeadSource,
    required this.onUpdateLeadScoreData,
    required this.onUpdateLeadParcelData,
    required this.onUpdateLeadReminderData,
    required this.onUpdateLeadOfferData,
    required this.onRefreshLeads,
    required this.onOpenAreas,
  });

  @override
  State<DrivingScreen> createState() => _DrivingScreenState();
}

class _DrivingScreenState extends State<DrivingScreen> {
  final MapController mapController = MapController();
  final GlobalKey mapWorkspaceKey = GlobalKey();

  LatLng currentMapCenter = const LatLng(36.2695, -95.8547);
  double currentZoom = 13;
  String selectedCoverageCity = MarketService.getActiveCity();
  LatLng? myLocation;
  Position? lastKnownPosition;
  bool isFindingLocation = false;
  bool followMyLocation = false;
  bool hasAttemptedInitialLocation = false;
  bool showRouteToStartLine = false;
  bool isTracking = false;
  bool isLoadingCoverage = true;
  bool isLoadingStreetCoverage = true;
  bool isLoadingVisibleStreets = false;
  bool isSyncingStreetCoverage = false;
  bool isLoadingParcel = false;
  bool isLoadingVisibleParcels = false;
  bool mapIsReady = false;
  String locationMessage = 'Location not found yet.';
  String? currentDriveSessionId;
  int gpsUpdateLogCounter = 0;

  final List<LatLng> routePoints = [];
  List<Lead> drivingLeads = [];
  List<DrivingPoint> savedDrivingPoints = [];
  List<CityStreet> cityStreets = [];
  List<ParcelProperty> visibleParcels = [];
  ParcelProperty? selectedParcel;
  int totalCityStreetCount = 0;
  Set<String> coveredStreetIds = {};
  StreamSubscription<Position>? positionStream;
  Timer? visibleParcelLoadTimer;
  Timer? visibleStreetLoadTimer;
  bool isHandlingTrackingPoint = false;
  LatLng? lastProcessedTrackingPoint;
  DateTime? lastProcessedTrackingPointAt;
  DateTime? lastMapFollowAt;
  List<DriveArea> driveAreas = [];
  DriveArea? activeDriveArea;
  List<LatLng> drawingAreaPoints = [];
  bool isDrawAreaMode = false;
  bool isLoadingDriveAreas = true;
  bool isSavingDriveArea = false;
  bool showOnlyActiveArea = false;
  bool showAllDriveAreaBoundaries = false;
  bool showSavedAreasWhileDrawing = false;
  bool firstMissionTipDismissed = false;
  List<CityReadiness> cityReadiness = [];
  DateTime? cityReadinessLoadedAt;
  bool isLoadingCityReadiness = false;
  List<String> recentMarketCities = [];
  List<MarketProperty> marketProperties = [];
  bool isLoadingMarketProperties = false;
  bool isBuildingMarketMap = false;
  int marketMapFetchedCount = 0;
  int marketMapSavedCount = 0;
  String marketMapMessage = '';
  String mapMode = 'mission';
  bool targetFilterOutOfState = false;
  bool targetFilterAbsentee = false;
  bool targetFilterPortfolio = false;
  bool targetFilterLowImprovement = false;
  bool showOnlyTargetsOnMap = false;
  Map<String, double> driveAreaRemainingOpportunity = {};
  List<StreetOpportunity> cachedStreetOpportunities = const [];
  String? cachedStreetOpportunityAreaId;
  int cachedStreetOpportunityStreetCount = -1;
  int cachedStreetOpportunityPropertyCount = -1;
  int cachedStreetOpportunityCoveredCount = -1;
  Mission? activeMission;
  List<Mission> completedMissions = [];
  List<Mission> scheduledMissions = [];
  Map<String, List<Lead>> missionLeadsById = {};
  bool hasCompletedMissionEver = false;
  bool isLoadingMissions = false;
  bool isSavingMission = false;
  bool hasShownActiveMissionResume = false;
  int fieldTestTitleTapCount = 0;
  Timer? fieldTestTitleTapResetTimer;
  int? selectedMissionTimeBudgetMinutes = 30;
  final customMissionTimeController = TextEditingController();
  bool customMissionTimeInHours = false;
  int? defaultSessionMinutes;
  bool timeMissionsEnabled = true;
  double calibrationFactor = 1.0;
  int calibrationMissionCount = 0;

  // Lead map filters (display-only; does not affect data or other layers).
  bool showLeadsOnMap = true;
  Set<String> selectedLeadStages = {...leadStatusOptions};
  bool useMinLeadScore = false;
  double minLeadScore = 0;

  @override
  void initState() {
    super.initState();
    drivingLeads = dedupeLeadsForDisplay(widget.leads);
    loadStartupData();
    loadMissionPlannerPreferences();
    loadFirstMissionTipPreference();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      locateOnDriveOpen();
    });
  }

  @override
  void didUpdateWidget(covariant DrivingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.leads != widget.leads) {
      drivingLeads = dedupeLeadsForDisplay(widget.leads);
    }
  }

  @override
  void dispose() {
    visibleParcelLoadTimer?.cancel();
    visibleStreetLoadTimer?.cancel();
    fieldTestTitleTapResetTimer?.cancel();
    positionStream?.cancel();
    customMissionTimeController.dispose();
    super.dispose();
  }

  void locateOnDriveOpen() {
    if (!mounted || hasAttemptedInitialLocation) return;

    hasAttemptedInitialLocation = true;
    unawaited(findMyLocation(reason: 'drive_open'));
  }

  void handleDriveTabVisible() {
    if (!mounted) return;

    if (myLocation == null && !isFindingLocation) {
      unawaited(findMyLocation(reason: 'drive_visible'));
    }
  }

  void handleDriveTabHidden() {
    if (!mounted) return;

    if (isTracking && activeMission == null) {
      unawaited(stopTracking());
      return;
    }

    if (!isTracking && followMyLocation) {
      setState(() {
        followMyLocation = false;
        locationMessage = 'Follow mode paused while Drive is hidden.';
      });
    }
  }

  Future<void> loadMissionPlannerPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      defaultSessionMinutes = prefs.getInt(defaultSessionMinutesPrefsKey);
      timeMissionsEnabled = prefs.getBool(timeMissionsEnabledPrefsKey) ?? true;
      calibrationFactor = prefs.getDouble(calibrationFactorPrefsKey) ?? 1.0;
      calibrationMissionCount =
          prefs.getInt(calibrationMissionCountPrefsKey) ?? 0;
    });
  }

  Future<void> loadFirstMissionTipPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      firstMissionTipDismissed =
          prefs.getBool(firstMissionTipDismissedPrefsKey) ?? false;
    });
  }

  Future<void> dismissFirstMissionTip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(firstMissionTipDismissedPrefsKey, true);
    if (!mounted) return;

    setState(() {
      firstMissionTipDismissed = true;
    });
  }

  Future<void> saveDefaultSessionMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(defaultSessionMinutesPrefsKey, minutes);
    if (!mounted) return;

    setState(() {
      defaultSessionMinutes = minutes;
      selectedMissionTimeBudgetMinutes = minutes;
    });
  }

  Future<void> saveTimeMissionsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(timeMissionsEnabledPrefsKey, value);
    if (!mounted) return;

    setState(() {
      timeMissionsEnabled = value;
    });
  }

  Future<void> saveCalibration({
    required double factor,
    required int count,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(calibrationFactorPrefsKey, factor);
    await prefs.setInt(calibrationMissionCountPrefsKey, count);
    if (!mounted) return;

    setState(() {
      calibrationFactor = factor;
      calibrationMissionCount = count;
    });
  }

  void handleFieldTestTitleTap() {
    fieldTestTitleTapResetTimer?.cancel();
    fieldTestTitleTapCount++;

    if (fieldTestTitleTapCount >= 5) {
      fieldTestTitleTapCount = 0;
      openFieldTestLogDialog();
      return;
    }

    fieldTestTitleTapResetTimer = Timer(const Duration(seconds: 2), () {
      fieldTestTitleTapCount = 0;
    });
  }

  void openFieldTestLogDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          const Dialog.fullscreen(child: FieldTestLogScreen()),
    );
  }

  Future<void> loadStartupData() async {
    await loadActiveCoverageCityPreference();
    unawaited(loadSavedDrivingPoints());
    unawaited(loadStreetCoverage());
    unawaited(loadDriveAreas());
    unawaited(loadCityReadiness());
    unawaited(loadCompletedMissionHistoryFlag());
  }

  Future<void> loadCompletedMissionHistoryFlag() async {
    try {
      final data = await supabase
          .from('missions')
          .select('id')
          .eq('account_id', widget.activeAccountId)
          .eq('status', 'completed')
          .limit(1);
      if (!mounted) return;

      setState(() {
        hasCompletedMissionEver = data.isNotEmpty;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        hasCompletedMissionEver = completedMissions.isNotEmpty;
      });
    }
  }

  Future<void> loadActiveCoverageCityPreference() async {
    await MarketService.initActiveCity();
    final prefs = await SharedPreferences.getInstance();
    final activeCity = MarketService.getActiveCity();
    final recentCities = prefs.getStringList(recentMarketCitiesPrefsKey) ?? [];
    if (!mounted) return;

    setState(() {
      selectedCoverageCity = activeCity;
      recentMarketCities = recentCities;
    });
  }

  Future<void> loadDrivingLeads() async {
    try {
      final data = await supabase
          .from('leads')
          .select()
          .eq('account_id', widget.activeAccountId)
          .order('created_at', ascending: false);
      final leads = dedupeLeadsForDisplay(
        data.map<Lead>((item) => Lead.fromMap(item)),
      );

      if (!mounted) return;

      setState(() {
        drivingLeads = leads;
      });
    } catch (_) {
      // Keep the currently loaded leads; lead save already reports failures.
    }
  }

  Future<void> loadSavedDrivingPoints() async {
    setState(() {
      isLoadingCoverage = true;
    });

    try {
      final data = await supabase
          .from('driving_points')
          .select()
          .eq('account_id', widget.activeAccountId);
      final drivingPoints = data
          .map<DrivingPoint>((item) => DrivingPoint.fromMap(item))
          .toList();

      drivingPoints.sort((a, b) {
        final aDate = a.createdAt;
        final bDate = b.createdAt;

        if (aDate == null || bDate == null) return 0;

        return aDate.compareTo(bDate);
      });

      if (!mounted) return;

      setState(() {
        savedDrivingPoints = drivingPoints;
        isLoadingCoverage = false;
      });

      await syncSavedDrivingPointsToStreetCoverage();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoadingCoverage = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load coverage points.')),
      );
    }
  }

  Future<void> loadStreetCoverage() async {
    setState(() {
      isLoadingStreetCoverage = true;
    });

    try {
      final coverageData = await supabase
          .from('street_coverage')
          .select('street_id')
          .eq('account_id', widget.activeAccountId)
          .eq('city', selectedCoverageCity);
      final statsData = await supabase
          .from('city_street_stats')
          .select('total_streets')
          .eq('city', selectedCoverageCity)
          .limit(1);
      final coveredIds = coverageData
          .map<String>((item) => item['street_id'].toString())
          .toSet();
      final totalStreets = statsData.isEmpty
          ? 0
          : ((statsData.first['total_streets'] ?? 0) as num).toInt();

      if (!mounted) return;

      setState(() {
        coveredStreetIds = coveredIds;
        totalCityStreetCount = totalStreets;
        clearStreetOpportunityCache();
        isLoadingStreetCoverage = false;
      });

      await loadVisibleCityStreets();
      await syncSavedDrivingPointsToStreetCoverage();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoadingStreetCoverage = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load street coverage.')),
      );
    }
  }

  Future<List<CityReadiness>> loadCityReadiness({
    bool forceRefresh = false,
  }) async {
    final loadedAt = cityReadinessLoadedAt;
    if (!forceRefresh &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < const Duration(minutes: 5)) {
      return cityReadiness;
    }

    if (mounted) {
      setState(() {
        isLoadingCityReadiness = true;
      });
    }

    try {
      final cityRows = await supabase
          .from('market_cities')
          .select()
          .order('state_code')
          .order('rank_in_state');
      final readiness = <CityReadiness>[];

      for (final row in cityRows) {
        int? parseInt(dynamic value) {
          if (value is int) return value;
          if (value is num) return value.toInt();
          return int.tryParse(value?.toString() ?? '');
        }

        double? parseDouble(dynamic value) {
          if (value is double) return value;
          if (value is num) return value.toDouble();
          return double.tryParse(value?.toString() ?? '');
        }

        final cityName =
            row['city']?.toString() ?? row['city_name']?.toString() ?? '';
        if (cityName.isEmpty) continue;
        final stateName = row['state']?.toString() ?? '';
        final stateCode = row['state_code']?.toString() ?? stateName;
        final marketStatus =
            row['market_status']?.toString() ??
            row['rollout_status']?.toString() ??
            'planned';
        if (marketStatus == 'disabled') continue;

        final streetRows = await supabase
            .from('city_streets')
            .select('id')
            .eq('city', cityName);
        final coverageRows = await supabase
            .from('street_coverage')
            .select('street_id')
            .eq('account_id', widget.activeAccountId)
            .eq('city', cityName);
        final areaRows = await supabase
            .from('drive_areas')
            .select('id,polygon')
            .eq('account_id', widget.activeAccountId)
            .eq('city', cityName);
        final areaIds = areaRows
            .map<String>((area) => area['id'].toString())
            .toList(growable: false);
        final propertyRows = areaIds.isEmpty
            ? const <Map<String, dynamic>>[]
            : await supabase
                  .from('properties')
                  .select('id,owner_name,target_score')
                  .eq('account_id', widget.activeAccountId)
                  .inFilter('drive_area_id', areaIds);
        final ownerInfoCount = propertyRows.where((property) {
          final ownerName = property['owner_name']?.toString().trim() ?? '';
          return ownerName.isNotEmpty;
        }).length;
        final propertyCount = propertyRows.length;
        final targetCount = propertyRows.where((property) {
          final score = parseDouble(property['target_score']) ?? 0;
          return score > 0;
        }).length;
        final cityPolygons = areaRows
            .map<List<LatLng>>((area) => parseDriveAreaPolygon(area['polygon']))
            .where((polygon) => polygon.length >= 3)
            .toList(growable: false);
        final leadCount = cityPolygons.isEmpty
            ? 0
            : drivingLeads.where((lead) {
                if (lead.latitude == null || lead.longitude == null) {
                  return false;
                }

                final point = LatLng(lead.latitude!, lead.longitude!);
                return cityPolygons.any(
                  (polygon) => pointInRing(point, polygon),
                );
              }).length;
        final ownerInfoPercent = propertyCount == 0
            ? 0.0
            : (ownerInfoCount / propertyCount) * 100;
        final displayName =
            row['display_name']?.toString().trim().isNotEmpty == true
            ? row['display_name'].toString()
            : stateCode.isEmpty
            ? cityName
            : '$cityName, $stateCode';

        readiness.add(
          CityReadiness(
            cityName: cityName,
            displayName: displayName,
            stateName: stateName,
            stateCode: stateCode,
            rankInState: parseInt(row['rank_in_state']),
            population: parseInt(row['population']),
            latitude: parseDouble(row['latitude']),
            longitude: parseDouble(row['longitude']),
            marketStatus: marketStatus,
            streetCount: streetRows.length,
            propertyCount: propertyCount,
            targetCount: targetCount,
            leadCount: leadCount,
            driveAreaCount: areaRows.length,
            coveredStreetCount: coverageRows.length,
            parcelServiceVerified: row['parcel_service_verified'] == true,
            streetImportStatus:
                row['street_import_status']?.toString() ?? 'none',
            marketMapBuilt: propertyCount > 0,
            ownerInfoPercent: ownerInfoPercent,
          ),
        );
      }

      if (!mounted) return readiness;

      setState(() {
        cityReadiness = readiness;
        cityReadinessLoadedAt = DateTime.now();
        isLoadingCityReadiness = false;
      });

      return readiness;
    } catch (_) {
      if (mounted) {
        setState(() {
          isLoadingCityReadiness = false;
        });
      }

      return cityReadiness;
    }
  }

  Future<void> loadDriveAreas() async {
    setState(() {
      isLoadingDriveAreas = true;
    });

    try {
      final data = await supabase
          .from('drive_areas')
          .select()
          .eq('account_id', widget.activeAccountId)
          .order('created_at', ascending: false);
      final areas = data
          .map<DriveArea>((item) => DriveArea.fromMap(item))
          .toList(growable: false);
      final activeArea = areas
          .where((area) => area.isActive && !area.isComplete)
          .firstOrNull;

      if (!mounted) return;

      final activeCity = activeArea?.city ?? '';
      final shouldChangeCity =
          activeCity.isNotEmpty && activeCity != selectedCoverageCity;

      setState(() {
        driveAreas = areas;
        activeDriveArea = activeArea;
        if (shouldChangeCity) {
          selectedCoverageCity = activeCity;
          cityStreets = [];
          coveredStreetIds = {};
          totalCityStreetCount = 0;
          clearStreetOpportunityCache();
        }
        isLoadingDriveAreas = false;
      });

      if (shouldChangeCity) {
        await loadStreetCoverage();
      }

      await loadDriveAreaPriorities(areas);
      await loadMarketProperties();
      await loadMissions();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoadingDriveAreas = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load drive areas.')),
      );
    }
  }

  Future<void> setActiveDriveArea(DriveArea? area) async {
    try {
      await supabase
          .from('drive_areas')
          .update({'is_active': false})
          .eq('account_id', widget.activeAccountId)
          .eq('is_active', true);

      if (area != null) {
        await supabase
            .from('drive_areas')
            .update({
              'is_active': true,
              'status': 'in_progress',
              'completed_at': null,
            })
            .eq('account_id', widget.activeAccountId)
            .eq('id', area.id);
      }

      await loadDriveAreas();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update active drive area.')),
      );
    }
  }

  Future<void> deleteDriveArea(DriveArea area) async {
    try {
      await supabase
          .from('properties')
          .delete()
          .eq('account_id', widget.activeAccountId)
          .eq('drive_area_id', area.id);
      await supabase
          .from('missions')
          .delete()
          .eq('account_id', widget.activeAccountId)
          .eq('drive_area_id', area.id);
      await supabase
          .from('drive_areas')
          .delete()
          .eq('account_id', widget.activeAccountId)
          .eq('id', area.id);

      if (!mounted) return;

      if (activeDriveArea?.id == area.id) {
        setState(() {
          activeDriveArea = null;
          marketProperties = [];
          activeMission = null;
          showRouteToStartLine = false;
        });
      }

      await loadDriveAreas();
      await loadMarketProperties();
      await loadMissions();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted ${area.name}.')));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete drive area.')),
      );
    }
  }

  Future<void> markActiveDriveAreaComplete() async {
    final area = activeDriveArea;
    if (area == null) return;

    try {
      await supabase
          .from('drive_areas')
          .update({
            'status': 'complete',
            'is_active': false,
            'completed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('account_id', widget.activeAccountId)
          .eq('id', area.id);

      await loadDriveAreas();
      await loadMarketProperties();
      await loadMissions();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not mark drive area complete.')),
      );
    }
  }

  Future<void> loadMarketProperties() async {
    final area = activeDriveArea;

    if (area == null) {
      if (!mounted) return;

      setState(() {
        marketProperties = [];
        clearStreetOpportunityCache();
        isLoadingMarketProperties = false;
      });
      return;
    }

    setState(() {
      isLoadingMarketProperties = true;
    });

    try {
      final data = await supabase
          .from('properties')
          .select()
          .eq('account_id', widget.activeAccountId)
          .eq('drive_area_id', area.id)
          .order('address');
      final properties = data
          .map<MarketProperty>((item) => MarketProperty.fromMap(item))
          .toList(growable: false);

      if (!mounted) return;

      setState(() {
        marketProperties = properties;
        clearStreetOpportunityCache();
        isLoadingMarketProperties = false;
      });

      if (properties.any((property) => !property.hasStoredScore)) {
        await scoreStoredMarketProperties(properties);
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoadingMarketProperties = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load market properties.')),
      );
    }
  }

  Future<void> loadDriveAreaPriorities(List<DriveArea> areas) async {
    if (areas.isEmpty) return;

    try {
      final areaIds = areas.map((area) => area.id).toList(growable: false);
      final data = await supabase
          .from('properties')
          .select('drive_area_id,target_score')
          .eq('account_id', widget.activeAccountId)
          .inFilter('drive_area_id', areaIds);
      final priorities = <String, double>{};

      for (final row in data) {
        final areaId = row['drive_area_id']?.toString();
        final score = (row['target_score'] as num?)?.toDouble() ?? 0;

        if (areaId == null || areaId.isEmpty) continue;

        priorities[areaId] = (priorities[areaId] ?? 0) + score;
      }

      if (!mounted) return;

      setState(() {
        driveAreaRemainingOpportunity = priorities;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        driveAreaRemainingOpportunity = {};
      });
    }
  }

  Future<void> loadMissions() async {
    final area = activeDriveArea;

    if (area == null) {
      if (!mounted) return;

      setState(() {
        activeMission = null;
        completedMissions = [];
        scheduledMissions = [];
        missionLeadsById = {};
        showRouteToStartLine = false;
        isLoadingMissions = false;
      });
      return;
    }

    setState(() {
      isLoadingMissions = true;
    });

    try {
      final data = await supabase
          .from('missions')
          .select()
          .eq('account_id', widget.activeAccountId)
          .eq('drive_area_id', area.id)
          .order('created_at', ascending: false);
      final missions = data
          .map<Mission>((item) => Mission.fromMap(item))
          .toList(growable: false);
      final openMission = missions
          .where((mission) => mission.isOpen)
          .firstOrNull;
      final completedForArea = missions
          .where((mission) => mission.status == 'completed')
          .toList(growable: false);

      if (!mounted) return;

      setState(() {
        activeMission = openMission;
        if (openMission == null) {
          showRouteToStartLine = false;
        }
        completedMissions = completedForArea;
        if (completedForArea.isNotEmpty) {
          hasCompletedMissionEver = true;
        }
        scheduledMissions = missions
            .where((mission) => mission.isScheduled)
            .toList(growable: false);
        isLoadingMissions = false;
      });

      await reconcilePersistedActiveMission(openMission);

      final ledgerMissions = [
        ...missions.where((mission) => mission.status == 'completed'),
      ];
      if (openMission != null) ledgerMissions.insert(0, openMission);

      await loadMissionLeadLedger(ledgerMissions);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoadingMissions = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not load missions.')));
    }
  }

  Future<void> persistActiveMissionId(String missionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(activeMissionIdPrefsKey, missionId);
  }

  Future<void> clearPersistedActiveMissionId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(activeMissionIdPrefsKey);
  }

  Future<void> reconcilePersistedActiveMission(Mission? openMission) async {
    final prefs = await SharedPreferences.getInstance();
    final persistedMissionId = prefs.getString(activeMissionIdPrefsKey);
    if (persistedMissionId == null || persistedMissionId.isEmpty) {
      if (openMission != null && openMission.isActive) {
        await persistActiveMissionId(openMission.id);
      }
      return;
    }

    if (openMission == null || openMission.id != persistedMissionId) {
      try {
        final data = await supabase
            .from('missions')
            .select('status')
            .eq('account_id', widget.activeAccountId)
            .eq('id', persistedMissionId)
            .maybeSingle();
        if (data == null || data['status'] != 'active') {
          await clearPersistedActiveMissionId();
        }
      } catch (_) {
        // Keep the id; the next startup/connectivity restore can verify it.
      }
      return;
    }

    if (!openMission.isActive) {
      await clearPersistedActiveMissionId();
      return;
    }

    if (!mounted || hasShownActiveMissionResume) return;

    hasShownActiveMissionResume = true;
    unawaited(FieldTestLogger.log('mission_restored', detail: openMission.id));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Resumed your active mission.')),
    );
  }

  Future<void> loadMissionLeadLedger(List<Mission> missions) async {
    if (missions.isEmpty) {
      if (!mounted) return;

      setState(() {
        missionLeadsById = {};
      });
      return;
    }

    try {
      final missionIds = missions.map((mission) => mission.id).toList();
      final data = await supabase
          .from('leads')
          .select()
          .eq('account_id', widget.activeAccountId)
          .inFilter('mission_id', missionIds)
          .order('created_at', ascending: false);
      final grouped = <String, List<Lead>>{};

      for (final item in data) {
        final missionId = item['mission_id']?.toString();
        if (missionId == null || missionId.isEmpty) continue;

        grouped.putIfAbsent(missionId, () => []).add(Lead.fromMap(item));
      }

      if (!mounted) return;

      setState(() {
        missionLeadsById = grouped;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        missionLeadsById = {};
      });
    }
  }

  Future<void> updateCalibrationFromCompletedMissions() async {
    final area = activeDriveArea;
    if (area == null) return;

    try {
      final data = await supabase
          .from('missions')
          .select('estimated_minutes,actual_minutes')
          .eq('account_id', widget.activeAccountId)
          .eq('drive_area_id', area.id)
          .eq('status', 'completed');
      final ratios = <double>[];

      for (final row in data) {
        final estimated = (row['estimated_minutes'] as num?)?.toDouble() ?? 0;
        final actual = (row['actual_minutes'] as num?)?.toDouble() ?? 0;
        if (estimated <= 0 || actual <= 0) continue;

        final ratio = actual / estimated;
        if (ratio < 0.4 || ratio > 3.0) continue;

        ratios.add(ratio);
      }

      final factor = ratios.length < 3
          ? 1.0
          : (ratios.reduce((a, b) => a + b) / ratios.length).clamp(0.5, 2.0);

      await saveCalibration(factor: factor.toDouble(), count: ratios.length);
    } catch (_) {
      // Calibration is helpful but non-critical; keep the current factor.
    }
  }

  Mission startedMissionCopy(
    Mission mission, {
    required String sessionId,
    required DateTime startedAt,
    required LatLng startPoint,
  }) {
    return Mission(
      id: mission.id,
      driveAreaId: mission.driveAreaId,
      status: 'active',
      targetStreetIds: mission.targetStreetIds,
      streetCount: mission.streetCount,
      opportunityAtStart: mission.opportunityAtStart,
      leadsGenerated: mission.leadsGenerated,
      milesDriven: mission.milesDriven,
      streetsCovered: mission.streetsCovered,
      opportunityCaptured: mission.opportunityCaptured,
      timeBudgetMinutes: mission.timeBudgetMinutes,
      estimatedMinutes: mission.estimatedMinutes,
      actualMinutes: mission.actualMinutes,
      scheduledDate: mission.scheduledDate,
      weeklyPlanId: mission.weeklyPlanId,
      driveSessionId: sessionId,
      createdAt: mission.createdAt,
      startedAt: startedAt,
      missionStartLat: startPoint.latitude,
      missionStartLng: startPoint.longitude,
      missionStartedAt: startedAt,
      completedAt: mission.completedAt,
    );
  }

  Map<String, dynamic> missionStartFields({
    required Position position,
    required DateTime startedAt,
    String? sessionId,
  }) {
    final row = <String, dynamic>{
      'started_at': startedAt.toIso8601String(),
      'mission_start_lat': position.latitude,
      'mission_start_lng': position.longitude,
      'mission_started_at': startedAt.toIso8601String(),
    };

    if (sessionId != null) {
      row['drive_session_id'] = sessionId;
    }

    return row;
  }

  Future<Position?> requireMissionStartLocation() async {
    final found = await findMyLocation(reason: 'mission_start');
    final position = lastKnownPosition;

    if (found && position != null) return position;

    if (!mounted) return null;

    const message = 'Current location needed to start mission.';
    setState(() {
      locationMessage = message;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(message)));
    unawaited(FieldTestLogger.log('mission_start_location_missing'));
    return null;
  }

  String missionStartSaveErrorMessage(Object error, String fallback) {
    final details = error.toString().toLowerCase();
    if (details.contains('mission_start_lat') ||
        details.contains('mission_start_lng') ||
        details.contains('mission_started_at')) {
      return 'Mission start fields are missing. Run Supabase migration 0011_mission_start_location.sql.';
    }

    return fallback;
  }

  String? missionIdForPoint(LatLng? point) {
    final mission = activeMission;
    final areaPolygon = activeDriveArea?.polygon ?? const <LatLng>[];

    if (mission == null || !mission.isActive) return null;
    if (point == null || areaPolygon.length < 3) return null;
    if (!pointInRing(point, areaPolygon)) return null;

    return mission.id;
  }

  double calibratedStreetMinutes(CityStreet street) {
    return estimateStreetMinutes(street) * calibrationFactor;
  }

  int estimatedMinutesForMissionStreets(List<StreetOpportunity> streets) {
    return streets
        .fold<double>(
          0,
          (total, opportunity) =>
              total + calibratedStreetMinutes(opportunity.street),
        )
        .ceil();
  }

  int estimatedMinutesForStreets(Iterable<CityStreet> streets) {
    return streets
        .fold<double>(
          0,
          (total, street) => total + calibratedStreetMinutes(street),
        )
        .ceil();
  }

  List<StreetOpportunity> selectMissionStreetsForBudget(
    List<StreetOpportunity> streetOpportunities,
    int timeBudgetMinutes, {
    bool includeUnscored = false,
    bool forceAtLeastOne = false,
  }) {
    final candidates = uncoveredMissionCandidates(
      streetOpportunities,
      includeUnscored: includeUnscored,
    );
    final selected = <StreetOpportunity>[];
    var estimatedMinutes = 0.0;

    for (final opportunity in candidates) {
      final streetMinutes = calibratedStreetMinutes(opportunity.street);
      final wouldFit = estimatedMinutes + streetMinutes <= timeBudgetMinutes;

      if (!wouldFit) continue;

      selected.add(opportunity);
      estimatedMinutes += streetMinutes;
    }

    if (selected.isEmpty && forceAtLeastOne && candidates.isNotEmpty) {
      return [bestAvailableStreetForTinyWindow(candidates)];
    }

    return selected;
  }

  List<StreetOpportunity> uncoveredMissionCandidates(
    List<StreetOpportunity> streetOpportunities, {
    bool includeUnscored = false,
  }) {
    final candidates =
        streetOpportunities
            .where(
              (opportunity) =>
                  !opportunity.isCovered &&
                  (includeUnscored || opportunity.score > 0),
            )
            .toList()
          ..sort((a, b) {
            final scoreCompare = b.score.compareTo(a.score);
            if (scoreCompare != 0) return scoreCompare;

            return calibratedStreetMinutes(
              a.street,
            ).compareTo(calibratedStreetMinutes(b.street));
          });

    return candidates;
  }

  StreetOpportunity bestAvailableStreetForTinyWindow(
    List<StreetOpportunity> candidates,
  ) {
    final ranked = [...candidates]
      ..sort((a, b) {
        final timeCompare = calibratedStreetMinutes(
          a.street,
        ).compareTo(calibratedStreetMinutes(b.street));
        if (timeCompare != 0) return timeCompare;

        return b.score.compareTo(a.score);
      });

    return ranked.first;
  }

  List<StreetOpportunity> defaultMissionStreets(
    List<StreetOpportunity> streetOpportunities, {
    bool includeUnscored = false,
  }) {
    return uncoveredMissionCandidates(
      streetOpportunities,
      includeUnscored: includeUnscored,
    ).take(missionStreetCount).toList(growable: false);
  }

  Map<String, dynamic> missionRowForStreets(
    List<StreetOpportunity> missionStreets, {
    required String status,
    int? timeBudgetMinutes,
    DateTime? scheduledDate,
    String? weeklyPlanId,
  }) {
    final row = <String, dynamic>{
      'account_id': widget.activeAccountId,
      'created_by': supabase.auth.currentUser?.id,
      'drive_area_id': activeDriveArea?.id,
      'status': status,
      'target_street_ids': missionStreets
          .map((opportunity) => opportunity.street.id)
          .toList(growable: false),
      'street_count': missionStreets.length,
      'opportunity_at_start': missionStreets.fold<double>(
        0,
        (total, opportunity) => total + opportunity.score,
      ),
    };

    if (timeBudgetMinutes != null) {
      row['time_budget_minutes'] = timeBudgetMinutes;
      row['estimated_minutes'] = estimatedMinutesForMissionStreets(
        missionStreets,
      );
    }
    if (scheduledDate != null) {
      row['scheduled_date'] = isoDateOnly(scheduledDate);
    }
    if (weeklyPlanId != null) {
      row['weekly_plan_id'] = weeklyPlanId;
    }

    return row;
  }

  List<({DateTime date, List<StreetOpportunity> streets, int minutes})>
  weeklyPlanMissionPreviews(
    List<StreetOpportunity> streetOpportunities,
    List<DateTime> selectedDates,
    int sessionMinutes,
  ) {
    final alreadyPlannedStreetIds = <String>{};
    final previews =
        <({DateTime date, List<StreetOpportunity> streets, int minutes})>[];

    for (final date in selectedDates) {
      final availableOpportunities = streetOpportunities
          .where(
            (opportunity) =>
                !alreadyPlannedStreetIds.contains(opportunity.street.id),
          )
          .toList(growable: false);
      final streets = selectMissionStreetsForBudget(
        availableOpportunities,
        sessionMinutes,
      );

      alreadyPlannedStreetIds.addAll(
        streets.map((opportunity) => opportunity.street.id),
      );
      previews.add((
        date: date,
        streets: streets,
        minutes: estimatedMinutesForMissionStreets(streets),
      ));
    }

    return previews;
  }

  int? parsedCustomMissionMinutes() {
    final value = double.tryParse(customMissionTimeController.text.trim());
    if (value == null || value <= 0) return null;

    final minutes = customMissionTimeInHours ? value * 60 : value;
    return minutes.round();
  }

  Future<void> generateMission(
    List<StreetOpportunity> streetOpportunities, {
    int? timeBudgetMinutes,
    bool includeUnscored = false,
    bool forceAtLeastOne = false,
  }) async {
    final area = activeDriveArea;
    if (area == null || isSavingMission) return;

    final existingOpen = activeMission;
    if (existingOpen != null && existingOpen.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This area already has an open mission.')),
      );
      return;
    }

    final missionStreets = timeBudgetMinutes == null
        ? defaultMissionStreets(
            streetOpportunities,
            includeUnscored: includeUnscored,
          )
        : selectMissionStreetsForBudget(
            streetOpportunities,
            timeBudgetMinutes,
            includeUnscored: includeUnscored,
            forceAtLeastOne: forceAtLeastOne,
          );

    if (missionStreets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No uncovered opportunity streets found.'),
        ),
      );
      return;
    }

    final startPosition = await requireMissionStartLocation();
    if (startPosition == null) return;

    final startedAt = DateTime.now().toUtc();

    setState(() {
      isSavingMission = true;
    });

    try {
      final row = missionRowForStreets(
        missionStreets,
        status: 'active',
        timeBudgetMinutes: timeBudgetMinutes,
      );
      row.addAll(
        missionStartFields(position: startPosition, startedAt: startedAt),
      );

      final insertedMission = await supabase
          .from('missions')
          .insert(row)
          .select('id')
          .single();
      unawaited(
        FieldTestLogger.log(
          'mission_start',
          detail: insertedMission['id']?.toString(),
        ),
      );

      await loadMissions();

      if (!mounted) return;

      setState(() {
        isSavingMission = false;
      });

      focusStreetWorkspace(
        'mission',
        missionStreets.first.street,
        message: 'Mission started. Map focused on your first street.',
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isSavingMission = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            missionStartSaveErrorMessage(error, 'Could not start mission.'),
          ),
        ),
      );
    }
  }

  Future<bool> createWeeklyPlan({
    required List<DateTime> selectedDates,
    required int sessionMinutes,
    required List<
      ({DateTime date, List<StreetOpportunity> streets, int minutes})
    >
    previews,
  }) async {
    final area = activeDriveArea;
    if (area == null || isSavingMission) return false;

    final missionPreviews = previews
        .where((preview) => preview.streets.isNotEmpty)
        .toList(growable: false);
    if (missionPreviews.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No streets available for this plan.')),
      );
      return false;
    }

    setState(() {
      isSavingMission = true;
    });

    try {
      final totalEstimatedMinutes = missionPreviews.fold<int>(
        0,
        (total, preview) => total + preview.minutes,
      );
      final weeklyPlan = await supabase
          .from('weekly_plans')
          .insert({
            'drive_area_id': area.id,
            'total_minutes': totalEstimatedMinutes,
            'available_days': selectedDates
                .map(
                  (date) => {
                    'date': isoDateOnly(date),
                    'weekday': shortWeekdayLabel(date),
                  },
                )
                .toList(growable: false),
            'minutes_per_session': sessionMinutes,
            'sessions_planned': missionPreviews.length,
            'week_start': isoDateOnly(DateTime.now()),
            'status': 'active',
          })
          .select('id')
          .single();
      final weeklyPlanId = weeklyPlan['id'].toString();
      final missionRows = missionPreviews
          .map(
            (preview) => missionRowForStreets(
              preview.streets,
              status: 'scheduled',
              timeBudgetMinutes: sessionMinutes,
              scheduledDate: preview.date,
              weeklyPlanId: weeklyPlanId,
            ),
          )
          .toList(growable: false);

      await supabase.from('missions').insert(missionRows);
      await loadMissions();

      if (!mounted) return false;

      setState(() {
        isSavingMission = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weekly driving plan created.')),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;

      setState(() {
        isSavingMission = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create weekly plan.')),
      );
      return false;
    }
  }

  Future<void> startScheduledMission(Mission mission) async {
    if (isSavingMission) return;

    final startPosition = await requireMissionStartLocation();
    if (startPosition == null) return;

    final sessionId = 'mission-${DateTime.now().millisecondsSinceEpoch}';
    final startedAt = DateTime.now().toUtc();

    setState(() {
      isSavingMission = true;
      currentDriveSessionId = sessionId;
    });

    try {
      await supabase
          .from('missions')
          .update({
            'status': 'active',
            ...missionStartFields(
              position: startPosition,
              startedAt: startedAt,
              sessionId: sessionId,
            ),
          })
          .eq('account_id', widget.activeAccountId)
          .eq('id', mission.id);
      unawaited(FieldTestLogger.log('mission_start', detail: mission.id));

      setState(() {
        activeMission = startedMissionCopy(
          mission,
          sessionId: sessionId,
          startedAt: startedAt,
          startPoint: LatLng(startPosition.latitude, startPosition.longitude),
        );
        scheduledMissions = scheduledMissions
            .where((item) => item.id != mission.id)
            .toList(growable: false);
        showRouteToStartLine = false;
      });
      await startTracking(sessionIdOverride: sessionId);
      unawaited(loadMissions());

      if (!mounted) return;

      setState(() {
        isSavingMission = false;
      });

      final firstStreet = mission.targetStreetIds.firstOrNull;
      final firstOpportunity = firstStreet == null
          ? null
          : cachedStreetOpportunitiesForActiveArea(
                  activeDriveArea == null
                      ? const <CityStreet>[]
                      : streetsInsideArea(activeDriveArea!),
                  marketProperties,
                )
                .where((opportunity) => opportunity.street.id == firstStreet)
                .firstOrNull;
      if (firstOpportunity != null) {
        focusStreetWorkspace(
          'mission',
          firstOpportunity.street,
          message: 'Mission started. Map focused on your first street.',
        );
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isSavingMission = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            missionStartSaveErrorMessage(
              error,
              'Could not start planned mission.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> skipScheduledMission(Mission mission) async {
    try {
      await supabase
          .from('missions')
          .update({'status': 'skipped'})
          .eq('account_id', widget.activeAccountId)
          .eq('id', mission.id);
      await loadMissions();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not skip planned mission.')),
      );
    }
  }

  Future<void> startMissionDriving() async {
    final mission = activeMission;
    if (mission == null || isSavingMission) return;

    final startPosition = await requireMissionStartLocation();
    if (startPosition == null) return;

    final sessionId = 'mission-${DateTime.now().millisecondsSinceEpoch}';
    final startedAt = mission.startedAt?.toUtc() ?? DateTime.now().toUtc();

    setState(() {
      isSavingMission = true;
      currentDriveSessionId = sessionId;
    });

    try {
      await supabase
          .from('missions')
          .update({
            'status': 'active',
            ...missionStartFields(
              position: startPosition,
              startedAt: startedAt,
              sessionId: sessionId,
            ),
          })
          .eq('account_id', widget.activeAccountId)
          .eq('id', mission.id);
      unawaited(FieldTestLogger.log('mission_start', detail: mission.id));

      setState(() {
        activeMission = startedMissionCopy(
          mission,
          sessionId: sessionId,
          startedAt: startedAt,
          startPoint: LatLng(startPosition.latitude, startPosition.longitude),
        );
        showRouteToStartLine = false;
      });
      await startTracking(sessionIdOverride: sessionId);
      unawaited(loadMissions());

      if (!mounted) return;

      setState(() {
        isSavingMission = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isSavingMission = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            missionStartSaveErrorMessage(
              error,
              'Could not start mission driving.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> pauseMission() async {
    final mission = activeMission;
    if (mission == null) return;

    try {
      if (isTracking) {
        await stopTracking();
      }

      await supabase
          .from('missions')
          .update({'status': 'paused'})
          .eq('account_id', widget.activeAccountId)
          .eq('id', mission.id);
      await clearPersistedActiveMissionId();
      if (mounted) {
        setState(() {
          showRouteToStartLine = false;
        });
      }
      await loadMissions();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not pause mission.')));
    }
  }

  Future<void> completeMission({
    required int streetsCovered,
    required double opportunityCaptured,
    required int leadsFound,
    required double milesDriven,
    BuildContext? closeContext,
  }) async {
    final mission = activeMission;
    if (mission == null || !mission.isOpen) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active mission to complete.')),
      );
      return;
    }

    final streetTotal = missionStreetTotalFor(mission);
    final savedStreetsCovered = streetsCovered.clamp(0, streetTotal).toInt();
    final savedOpportunityCaptured = safeMissionOpportunityCaptured(
      opportunityAtStart: mission.opportunityAtStart,
      opportunityRemaining: mission.opportunityAtStart - opportunityCaptured,
    );
    final savedLeadsFound = math.max(0, leadsFound).toInt();
    final savedMilesDriven = math.max(0.0, milesDriven);

    try {
      if (isTracking) {
        await stopTracking();
      }

      final completedAt = DateTime.now().toUtc();
      final startedAt = mission.startedAt?.toUtc();
      final actualMinutes = startedAt == null
          ? null
          : completedAt.difference(startedAt).inMinutes;
      final missionUpdate = <String, dynamic>{
        'status': 'completed',
        'completed_at': completedAt.toIso8601String(),
        'leads_generated': savedLeadsFound,
        'miles_driven': savedMilesDriven,
        'streets_covered': savedStreetsCovered,
        'opportunity_captured': savedOpportunityCaptured,
      };
      if (actualMinutes != null) {
        missionUpdate['actual_minutes'] = actualMinutes;
      }

      await supabase
          .from('missions')
          .update(missionUpdate)
          .eq('account_id', widget.activeAccountId)
          .eq('id', mission.id);
      unawaited(
        FieldTestLogger.log(
          'mission_complete',
          detail: 'streets: $savedStreetsCovered, leads: $savedLeadsFound',
        ),
      );
      await clearPersistedActiveMissionId();

      await updateCalibrationFromCompletedMissions();

      final attributedLeads = leadsForMission(mission);
      final remainingAreaMinutes = activeDriveArea == null
          ? 0
          : estimatedMinutesForStreets(
              streetsInsideArea(
                activeDriveArea!,
              ).where((street) => !coveredStreetIds.contains(street.id)),
            );
      await loadMissions();

      if (!mounted) return;

      setState(() {
        mapMode = 'drive';
        locationMessage = 'Mission completed.';
        showRouteToStartLine = false;
      });

      if (closeContext != null && closeContext.mounted) {
        await Navigator.of(closeContext).maybePop();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }

      if (!mounted) return;

      openMissionResults(
        mission: mission,
        areaName: activeDriveArea?.name ?? 'Drive Area',
        leads: attributedLeads,
        streetsCovered: savedStreetsCovered,
        opportunityCaptured: savedOpportunityCaptured,
        milesDriven: savedMilesDriven,
        actualMinutes: actualMinutes,
        areaRemainingEstimatedMinutes: remainingAreaMinutes,
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not complete mission.')),
      );
    }
  }

  void openMissionResults({
    required Mission mission,
    required String areaName,
    required List<Lead> leads,
    required int streetsCovered,
    required double opportunityCaptured,
    required double milesDriven,
    int? actualMinutes,
    int areaRemainingEstimatedMinutes = 0,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => MissionResultsSheet(
        mission: mission,
        areaName: areaName,
        leads: leads,
        streetsCovered: streetsCovered,
        opportunityCaptured: opportunityCaptured,
        milesDriven: milesDriven,
        actualMinutes: actualMinutes,
        areaRemainingEstimatedMinutes: areaRemainingEstimatedMinutes,
        onUpdateLeadStatus: widget.onUpdateLeadStatus,
        onUpdateLeadSource: widget.onUpdateLeadSource,
        onUpdateLeadScoreData: widget.onUpdateLeadScoreData,
        onUpdateLeadParcelData: widget.onUpdateLeadParcelData,
        onUpdateLeadReminderData: widget.onUpdateLeadReminderData,
        onUpdateLeadOfferData: widget.onUpdateLeadOfferData,
      ),
    );
  }

  String quickCaptureCondition({
    required bool roofDamage,
    required bool brokenWindows,
    required bool trashInYard,
    required bool vacantAppearance,
    required bool exteriorWear,
    required bool tallGrass,
  }) {
    if (roofDamage) return 'Roof Damage';
    if (brokenWindows) return 'Broken Windows';
    if (trashInYard) return 'Trash';
    if (vacantAppearance) return 'Vacant';
    if (exteriorWear) return 'Bad Shape';
    if (tallGrass) return 'Tall Grass';

    return 'Distressed Property';
  }

  Future<QuickCaptureSaveResult> saveQuickCaptureParcelLead({
    required ParcelProperty parcel,
    required LeadScoreData scoreData,
    required String condition,
    required String notes,
  }) async {
    final leadLocation = parcel.centroid;
    final missionId = missionIdForPoint(leadLocation);
    final row = {
      'user_id': supabase.auth.currentUser?.id,
      'account_id': widget.activeAccountId,
      'created_by': supabase.auth.currentUser?.id,
      'address': parcel.displayAddress,
      'condition': condition,
      'notes': notes.isEmpty ? parcel.leadNotes : notes,
      'status': 'New Lead',
      'source': 'Driving For Dollars',
      ...scoreData.toMap(),
      'latitude': leadLocation?.latitude,
      'longitude': leadLocation?.longitude,
      'owner_name': parcel.ownerName ?? '',
      'mailing_address': parcel.mailingAddress ?? '',
      'out_of_state_owner': parcel.outOfStateOwner,
      'assessed_value': parcel.assessedValue,
      'property_type': parcel.propertyType ?? '',
      'lot_size': parcel.lotSizeDisplay,
      'year_built': parcel.yearBuilt,
      'last_sale_date': parcel.saleDate,
      'last_sale_price': parcel.salePrice,
      'deed_type': parcel.deedType,
      'document_date': parcel.documentDate,
      'reception_no': parcel.receptionNo,
      if (parcel.targetScore != null) 'target_score': parcel.targetScore,
    };
    if (missionId != null) row['mission_id'] = missionId;

    final result = await insertLeadWithOfflineQueue(row);

    if (result.savedOnline) {
      await loadDrivingLeads();
      await widget.onRefreshLeads();
      final ledgerMissions = [...completedMissions];
      if (activeMission != null) {
        ledgerMissions.insert(0, activeMission!);
      }
      await loadMissionLeadLedger(ledgerMissions);
    }

    return QuickCaptureSaveResult(
      lead: result.savedOnline ? leadForParcel(parcel) : null,
      queuedLocally: result.queuedLocally,
    );
  }

  Future<DuplicateLeadCandidate?> findDuplicateLeadNear(LatLng? point) async {
    if (point == null) return null;

    try {
      final data = await supabase
          .from('leads')
          .select('id,address')
          .eq('account_id', widget.activeAccountId)
          .gte('latitude', point.latitude - 0.0003)
          .lte('latitude', point.latitude + 0.0003)
          .gte('longitude', point.longitude - 0.0003)
          .lte('longitude', point.longitude + 0.0003)
          .limit(1)
          .timeout(duplicateLeadCheckTimeout);
      if (data.isEmpty) return null;

      final row = data.first;
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) return null;

      return DuplicateLeadCandidate(
        id: id,
        address: row['address']?.toString() ?? 'saved lead',
      );
    } catch (_) {
      return null;
    }
  }

  Future<Lead?> loadLeadById(String leadId) async {
    final localLead = drivingLeads
        .where((lead) => lead.id == leadId)
        .firstOrNull;
    if (localLead != null) return localLead;

    try {
      final data = await supabase
          .from('leads')
          .select()
          .eq('account_id', widget.activeAccountId)
          .eq('id', leadId)
          .maybeSingle()
          .timeout(duplicateLeadCheckTimeout);
      if (data == null) return null;

      return Lead.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  Future<bool> confirmQuickCaptureDuplicate({
    required ParcelProperty parcel,
    required BuildContext sheetContext,
  }) async {
    final duplicate = await findDuplicateLeadNear(parcel.centroid);
    if (duplicate == null || !mounted || !sheetContext.mounted) return true;
    unawaited(
      FieldTestLogger.log('qc_duplicate_detected', detail: duplicate.address),
    );

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('This may already be a lead'),
        content: Text(
          'This property may already be saved as a lead (${duplicate.address}). Save again or view the existing one?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'view'),
            child: const Text('View Existing Lead'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Save Anyway'),
          ),
        ],
      ),
    );

    if (action == 'save') return true;
    if (action == 'view') {
      final lead = await loadLeadById(duplicate.id);
      if (!mounted || !sheetContext.mounted) return false;

      Navigator.pop(sheetContext);
      if (lead != null) {
        openLeadDetails(lead);
      }
      return false;
    }

    return false;
  }

  void openManualLeadFromPoint(LatLng point) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddLeadScreen(
          onAddLead:
              (
                address,
                condition,
                notes,
                source,
                scoreData,
                latitude,
                longitude, [
                missionId,
              ]) async {
                await widget.onAddLead(
                  address,
                  condition,
                  notes,
                  source,
                  scoreData,
                  latitude,
                  longitude,
                  missionId,
                );
                await loadDrivingLeads();
                final ledgerMissions = [...completedMissions];
                if (activeMission != null) {
                  ledgerMissions.insert(0, activeMission!);
                }
                await loadMissionLeadLedger(ledgerMissions);
              },
          latitude: point.latitude,
          longitude: point.longitude,
          missionId: missionIdForPoint(point),
        ),
      ),
    );
  }

  void openQuickCaptureSheet() {
    unawaited(FieldTestLogger.log('qc_open'));
    final usedGpsForQuickCapture = myLocation != null;
    final quickCaptureAccuracyMeters = lastKnownPosition?.accuracy;
    final lookupPoint = myLocation ?? currentMapCenter;
    final noteController = TextEditingController();
    var fetchStarted = false;
    var isLoading = true;
    var isSaving = false;
    var parcelLoadFailed = false;
    ParcelProperty? quickParcel;
    Lead? existingLead;
    var tallGrass = false;
    var vacantAppearance = false;
    var roofDamage = false;
    var trashInYard = false;
    var brokenWindows = false;
    var exteriorWear = false;

    LeadScoreData currentScoreData() {
      final baseScore = calculateSmartLeadScore(
        vacantAppearance: vacantAppearance,
        roofDamage: roofDamage,
        trashInYard: trashInYard,
        brokenWindows: brokenWindows,
        tallGrass: tallGrass,
      );
      final score = (baseScore + (exteriorWear ? 8 : 0)).clamp(0, 100);

      return LeadScoreData(
        brokenWindows: brokenWindows,
        roofDamage: roofDamage,
        tallGrass: tallGrass,
        trashInYard: trashInYard,
        exteriorWear: exteriorWear,
        vacantAppearance: vacantAppearance,
        score: score,
        scoreOverride: false,
      );
    }

    Widget conditionChip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      final child = FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, textAlign: TextAlign.center),
      );

      return SizedBox(
        height: 56,
        child: selected
            ? FilledButton(onPressed: onTap, child: child)
            : OutlinedButton(onPressed: onTap, child: child),
      );
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          if (!fetchStarted) {
            fetchStarted = true;
            Future<void>(() async {
              ParcelProperty? foundParcel;

              try {
                foundParcel = await fetchParcelNearPoint(
                  lookupPoint,
                ).timeout(const Duration(seconds: 5));
              } catch (_) {
                foundParcel = null;
              }

              if (!mounted || !sheetContext.mounted) return;

              if (foundParcel == null) {
                unawaited(FieldTestLogger.log('qc_parcel_failed'));
              } else {
                unawaited(
                  FieldTestLogger.log(
                    'qc_parcel_found',
                    detail: foundParcel.displayAddress,
                  ),
                );
              }

              setSheetState(() {
                quickParcel = foundParcel;
                existingLead = foundParcel == null
                    ? null
                    : leadForParcel(foundParcel);
                parcelLoadFailed = foundParcel == null;
                isLoading = false;
              });
            });
          }

          final scoreData = currentScoreData();
          final gpsWarningText = !usedGpsForQuickCapture
              ? 'No GPS - using map center. Verify address.'
              : quickCaptureAccuracyMeters != null &&
                    quickCaptureAccuracyMeters > 30 &&
                    quickCaptureAccuracyMeters <= 80
              ? 'Weak GPS - nearby property may be off by a house or two. Confirm address.'
              : null;
          final gpsWarningColor = !usedGpsForQuickCapture
              ? const Color(0xFFB91C1C)
              : const Color(0xFFB45309);

          Future<void> saveQuickCapture({required bool openPhotos}) async {
            final parcel = quickParcel;
            if (parcel == null || isSaving) return;

            final proceed = await confirmQuickCaptureDuplicate(
              parcel: parcel,
              sheetContext: sheetContext,
            );
            if (!proceed || !mounted || !sheetContext.mounted) return;

            setSheetState(() {
              isSaving = true;
            });

            final condition = quickCaptureCondition(
              roofDamage: roofDamage,
              brokenWindows: brokenWindows,
              trashInYard: trashInYard,
              vacantAppearance: vacantAppearance,
              exteriorWear: exteriorWear,
              tallGrass: tallGrass,
            );

            try {
              unawaited(
                FieldTestLogger.log(
                  'qc_save_attempt',
                  detail: parcel.displayAddress,
                ),
              );
              final saveResult = await saveQuickCaptureParcelLead(
                parcel: parcel,
                scoreData: currentScoreData(),
                condition: condition,
                notes: noteController.text.trim(),
              );
              final savedLead = saveResult.lead;
              unawaited(
                FieldTestLogger.log(
                  saveResult.queuedLocally
                      ? 'qc_save_queued'
                      : 'qc_save_success',
                ),
              );

              if (!mounted || !sheetContext.mounted) return;

              Navigator.pop(sheetContext);
              if (openPhotos && savedLead != null) {
                openLeadDetails(savedLead);
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                  showCloseIcon: true,
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 112),
                  content: Text(
                    saveResult.queuedLocally
                        ? 'Lead saved locally - will sync when connected.'
                        : 'Lead saved - ${parcel.displayAddress}.',
                  ),
                  action: savedLead == null || saveResult.queuedLocally
                      ? null
                      : SnackBarAction(
                          label: 'View ->',
                          onPressed: () => openLeadDetails(savedLead),
                        ),
                ),
              );
            } catch (_) {
              unawaited(FieldTestLogger.log('qc_save_failed'));
              if (!mounted || !sheetContext.mounted) return;

              setSheetState(() {
                isSaving = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Couldn't save lead. Try again.")),
              );
            }
          }

          return SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.68,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 18,
                  right: 18,
                  bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 14),
                            Text('Finding nearby property...'),
                          ],
                        ),
                      )
                    : parcelLoadFailed
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 42,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'No property found nearby.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            icon: const Icon(Icons.edit_location_alt),
                            label: const Text('Save with manual address ->'),
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              openManualLeadFromPoint(lookupPoint);
                            },
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Cancel'),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    quickParcel?.displayAddress.isNotEmpty ??
                                            false
                                        ? quickParcel!.displayAddress
                                        : 'Unknown Property',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                leadScoreBadge(scoreData.score, fontSize: 16),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    quickParcel?.ownerName ?? 'Owner not set',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (quickParcel?.outOfStateOwner ?? false)
                                  const Chip(
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: Color(0xFFFFF3CD),
                                    label: Text('⚠ OOS'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Built ${quickParcel?.yearBuilt?.toString() ?? 'Not set'} · Assessed ${formatMoney(quickParcel?.assessedValue)}',
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 13,
                              ),
                            ),
                            if (gpsWarningText != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                gpsWarningText,
                                style: TextStyle(
                                  color: gpsWarningColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (existingLead != null) ...[
                              Row(
                                children: [
                                  leadStageBadge(existingLead!.status),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Already a lead',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('View existing lead ->'),
                                onPressed: () {
                                  final lead = existingLead!;
                                  Navigator.pop(sheetContext);
                                  openLeadDetails(lead);
                                },
                              ),
                            ] else ...[
                              const Text(
                                'What did you see?',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 10),
                              GridView.count(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisCount: 3,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 1.55,
                                children: [
                                  conditionChip(
                                    label: '🌿 Tall Grass',
                                    selected: tallGrass,
                                    onTap: () => setSheetState(
                                      () => tallGrass = !tallGrass,
                                    ),
                                  ),
                                  conditionChip(
                                    label: '🏚 Vacant',
                                    selected: vacantAppearance,
                                    onTap: () => setSheetState(
                                      () =>
                                          vacantAppearance = !vacantAppearance,
                                    ),
                                  ),
                                  conditionChip(
                                    label: '🏗 Roof Damage',
                                    selected: roofDamage,
                                    onTap: () => setSheetState(
                                      () => roofDamage = !roofDamage,
                                    ),
                                  ),
                                  conditionChip(
                                    label: '🗑 Trash',
                                    selected: trashInYard,
                                    onTap: () => setSheetState(
                                      () => trashInYard = !trashInYard,
                                    ),
                                  ),
                                  conditionChip(
                                    label: '🪟 Broken Windows',
                                    selected: brokenWindows,
                                    onTap: () => setSheetState(
                                      () => brokenWindows = !brokenWindows,
                                    ),
                                  ),
                                  conditionChip(
                                    label: '💀 Bad Shape',
                                    selected: exteriorWear,
                                    onTap: () => setSheetState(
                                      () => exteriorWear = !exteriorWear,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: noteController,
                                minLines: 1,
                                maxLines: 1,
                                decoration: const InputDecoration(
                                  hintText: 'Quick note (optional)',
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                icon: const Icon(Icons.check),
                                label: Text(
                                  isSaving ? 'Saving...' : 'Save Lead →',
                                ),
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        final parcel = quickParcel;
                                        if (parcel == null) return;

                                        final proceed =
                                            await confirmQuickCaptureDuplicate(
                                              parcel: parcel,
                                              sheetContext: sheetContext,
                                            );
                                        if (!proceed ||
                                            !mounted ||
                                            !sheetContext.mounted) {
                                          return;
                                        }

                                        setSheetState(() {
                                          isSaving = true;
                                        });

                                        final condition = quickCaptureCondition(
                                          roofDamage: roofDamage,
                                          brokenWindows: brokenWindows,
                                          trashInYard: trashInYard,
                                          vacantAppearance: vacantAppearance,
                                          exteriorWear: exteriorWear,
                                          tallGrass: tallGrass,
                                        );

                                        try {
                                          unawaited(
                                            FieldTestLogger.log(
                                              'qc_save_attempt',
                                              detail: parcel.displayAddress,
                                            ),
                                          );
                                          final saveResult =
                                              await saveQuickCaptureParcelLead(
                                                parcel: parcel,
                                                scoreData: currentScoreData(),
                                                condition: condition,
                                                notes: noteController.text
                                                    .trim(),
                                              );
                                          final savedLead = saveResult.lead;
                                          unawaited(
                                            FieldTestLogger.log(
                                              saveResult.queuedLocally
                                                  ? 'qc_save_queued'
                                                  : 'qc_save_success',
                                            ),
                                          );

                                          if (!mounted ||
                                              !sheetContext.mounted) {
                                            return;
                                          }

                                          Navigator.pop(sheetContext);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              duration: const Duration(
                                                seconds: 2,
                                              ),
                                              showCloseIcon: true,
                                              margin: const EdgeInsets.fromLTRB(
                                                12,
                                                0,
                                                12,
                                                112,
                                              ),
                                              content: Text(
                                                saveResult.queuedLocally
                                                    ? 'Lead saved locally - will sync when connected.'
                                                    : 'Lead saved - ${parcel.displayAddress}.',
                                              ),
                                              action:
                                                  savedLead == null ||
                                                      saveResult.queuedLocally
                                                  ? null
                                                  : SnackBarAction(
                                                      label: 'View →',
                                                      onPressed: () =>
                                                          openLeadDetails(
                                                            savedLead,
                                                          ),
                                                    ),
                                            ),
                                          );
                                        } catch (_) {
                                          unawaited(
                                            FieldTestLogger.log(
                                              'qc_save_failed',
                                            ),
                                          );
                                          if (!mounted ||
                                              !sheetContext.mounted) {
                                            return;
                                          }

                                          setSheetState(() {
                                            isSaving = false;
                                          });
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                "Couldn't save lead. Try again.",
                                              ),
                                            ),
                                          );
                                        }
                                      },
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.photo_camera),
                                label: Text(
                                  isSaving ? 'Saving...' : 'Save + Photos ->',
                                ),
                                onPressed: isSaving
                                    ? null
                                    : () => saveQuickCapture(openPhotos: true),
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(noteController.dispose);
  }

  void openWeeklyPlannerSheet(List<StreetOpportunity> streetOpportunities) {
    final today = dateOnly(DateTime.now());
    final plannerDates = List.generate(
      7,
      (index) => today.add(Duration(days: index)),
    );
    final selectedDayKeys = <String>{};
    var step = 0;
    var sessionMinutes = defaultSessionMinutes ?? 30;
    var isCustom = false;
    final customController = TextEditingController(
      text: sessionMinutes.toString(),
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final selectedDates = plannerDates
              .where((date) => selectedDayKeys.contains(isoDateOnly(date)))
              .toList(growable: false);
          final previews = weeklyPlanMissionPreviews(
            streetOpportunities,
            selectedDates,
            sessionMinutes,
          );
          final totalMinutes = previews.fold<int>(
            0,
            (total, preview) => total + preview.minutes,
          );
          final areaStreets = activeDriveArea == null
              ? const <CityStreet>[]
              : streetsInsideArea(activeDriveArea!);
          final uncoveredAreaMinutes = estimatedMinutesForStreets(
            areaStreets.where(
              (street) => !coveredStreetIds.contains(street.id),
            ),
          );
          final sessionsToFinish = sessionMinutes <= 0
              ? 0
              : (uncoveredAreaMinutes / sessionMinutes).ceil();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Plan my week',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Which days this week?',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: plannerDates.map((date) {
                        final key = isoDateOnly(date);
                        final selected = selectedDayKeys.contains(key);

                        return FilterChip(
                          label: Text(shortWeekdayLabel(date)),
                          selected: selected,
                          onSelected: (value) {
                            setSheetState(() {
                              if (value) {
                                selectedDayKeys.add(key);
                              } else {
                                selectedDayKeys.remove(key);
                              }
                              step = selectedDayKeys.isEmpty
                                  ? 0
                                  : math.max(step, 1);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (selectedDayKeys.isEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Pick at least one day to continue.',
                        style: TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ],
                    if (step >= 1) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'How long each session?',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('30 min'),
                            selected: sessionMinutes == 30 && !isCustom,
                            onSelected: (_) {
                              setSheetState(() {
                                sessionMinutes = 30;
                                isCustom = false;
                                step = 2;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('45 min'),
                            selected: sessionMinutes == 45 && !isCustom,
                            onSelected: (_) {
                              setSheetState(() {
                                sessionMinutes = 45;
                                isCustom = false;
                                step = 2;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('1 hour'),
                            selected: sessionMinutes == 60 && !isCustom,
                            onSelected: (_) {
                              setSheetState(() {
                                sessionMinutes = 60;
                                isCustom = false;
                                step = 2;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Custom'),
                            selected: isCustom,
                            onSelected: (_) {
                              setSheetState(() {
                                isCustom = true;
                              });
                            },
                          ),
                        ],
                      ),
                      if (isCustom) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: customController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Minutes',
                            suffixText: 'min',
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () {
                            final customMinutes = int.tryParse(
                              customController.text.trim(),
                            );
                            if (customMinutes == null || customMinutes <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Enter a valid session length.',
                                  ),
                                ),
                              );
                              return;
                            }

                            setSheetState(() {
                              sessionMinutes = customMinutes;
                              step = 2;
                            });
                          },
                          child: const Text('Use custom time'),
                        ),
                      ],
                    ],
                    if (step >= 2) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'Plan preview',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (previews.isEmpty)
                        const Text('No days selected.')
                      else
                        ...previews.map(
                          (preview) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(shortPlannerDateLabel(preview.date)),
                            subtitle: Text(
                              '${preview.streets.length} streets - ~${preview.minutes} min',
                            ),
                          ),
                        ),
                      const Divider(),
                      Text(
                        '$totalMinutes total planned minutes - about $sessionsToFinish sessions to finish this area',
                        style: const TextStyle(color: Color(0xFF6B7280)),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Create This Plan ->'),
                        onPressed: isSavingMission
                            ? null
                            : () async {
                                final created = await createWeeklyPlan(
                                  selectedDates: selectedDates,
                                  sessionMinutes: sessionMinutes,
                                  previews: previews,
                                );
                                if (created && sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                              },
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(customController.dispose);
  }

  void openPlanTodayDriveSheet(List<StreetOpportunity> streetOpportunities) {
    var step = !timeMissionsEnabled
        ? activeDriveArea == null
              ? 1
              : 2
        : defaultSessionMinutes == null
        ? 0
        : activeDriveArea == null
        ? 1
        : 2;
    int? selectedBudget = timeMissionsEnabled
        ? (defaultSessionMinutes ?? selectedMissionTimeBudgetMinutes ?? 30)
        : null;
    var showAreaList = false;
    var isCustom = false;
    var rememberAsDefault = false;
    final customController = TextEditingController();

    List<StreetOpportunity> sheetStreetOpportunities(
      List<CityStreet> areaStreets,
      List<MarketProperty> areaMarketProperties,
    ) {
      final area = activeDriveArea;
      if (area == null) return streetOpportunities;

      return cachedStreetOpportunitiesForActiveArea(
        areaStreets,
        areaMarketProperties,
      );
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final areaStreets = activeDriveArea == null
              ? const <CityStreet>[]
              : streetsInsideArea(activeDriveArea!);
          final areaCoveredStreetCount = areaStreets
              .where((street) => coveredStreetIds.contains(street.id))
              .length;
          final areaUncoveredStreets = areaStreets
              .where((street) => !coveredStreetIds.contains(street.id))
              .toList(growable: false);
          final areaCoveragePercent = areaStreets.isEmpty
              ? 0.0
              : (areaCoveredStreetCount / areaStreets.length) * 100;
          final areaRemainingMinutes = estimatedMinutesForStreets(
            areaUncoveredStreets,
          );
          final sessionBudgetForEstimate =
              selectedBudget ?? defaultSessionMinutes ?? 30;
          final sessionsToFinish = sessionBudgetForEstimate <= 0
              ? 0
              : (areaRemainingMinutes / sessionBudgetForEstimate).ceil();
          final hasAreaStreetData = areaStreets.isNotEmpty;
          final hasUncoveredAreaStreets = areaUncoveredStreets.isNotEmpty;
          final areaMarketProperties = activeDriveArea == null
              ? const <MarketProperty>[]
              : _marketPropertiesForArea(this, activeDriveArea!);
          final currentStreetOpportunities = sheetStreetOpportunities(
            areaStreets,
            areaMarketProperties,
          );
          final hasMarketMapData = areaMarketProperties.isNotEmpty;
          final includeUnscoredMissionStreets =
              hasMarketMapData && hasAreaStreetData;
          final previewStreets = timeMissionsEnabled && selectedBudget != null
              ? selectMissionStreetsForBudget(
                  currentStreetOpportunities,
                  selectedBudget!,
                  includeUnscored: includeUnscoredMissionStreets,
                )
              : defaultMissionStreets(
                  currentStreetOpportunities,
                  includeUnscored: includeUnscoredMissionStreets,
                );
          final forcedBestAvailableStreets =
              timeMissionsEnabled && selectedBudget != null
              ? selectMissionStreetsForBudget(
                  currentStreetOpportunities,
                  selectedBudget!,
                  includeUnscored: includeUnscoredMissionStreets,
                  forceAtLeastOne: true,
                )
              : const <StreetOpportunity>[];
          final previewMinutes = estimatedMinutesForMissionStreets(
            previewStreets,
          );
          final missionRemainingCoveragePercent = areaUncoveredStreets.isEmpty
              ? 0.0
              : (previewStreets.length / areaUncoveredStreets.length) * 100;
          final noMarketMapForArea =
              hasAreaStreetData && hasUncoveredAreaStreets && !hasMarketMapData;
          final noTimeFit =
              timeMissionsEnabled &&
              selectedBudget != null &&
              hasAreaStreetData &&
              hasUncoveredAreaStreets &&
              hasMarketMapData &&
              previewStreets.isEmpty;
          final noUncoveredStreets =
              hasAreaStreetData && !hasUncoveredAreaStreets;
          final availableTimeLabel = selectedBudget == null
              ? 'Default mission'
              : '$selectedBudget min available';
          final previewTitle = noMarketMapForArea
              ? 'Analyze the area to unlock time estimates.'
              : noTimeFit
              ? 'No streets fit this time window.'
              : noUncoveredStreets
              ? 'Area streets are already covered.'
              : previewStreets.isEmpty
              ? 'No available mission streets.'
              : '${previewStreets.length} streets - ~$previewMinutes min';
          final previewHelper = noMarketMapForArea
              ? 'Area analysis is needed before the time planner can rank streets here.'
              : noTimeFit
              ? 'Increase your time or start a default mission.'
              : calibrationMissionCount >= 3
              ? 'Based on your driving history'
              : 'Estimated at 10 mph scouting speed';

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    step == 0
                        ? 'How much time?'
                        : step == 1
                        ? 'Drive Area'
                        : 'Mission preview',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (step == 0) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('30 min'),
                          selected: selectedBudget == 30 && !isCustom,
                          onSelected: (_) async {
                            if (rememberAsDefault) {
                              await saveDefaultSessionMinutes(30);
                            }
                            if (!mounted) return;
                            setSheetState(() {
                              selectedBudget = 30;
                              isCustom = false;
                              step = 1;
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('1 hour'),
                          selected: selectedBudget == 60 && !isCustom,
                          onSelected: (_) async {
                            if (rememberAsDefault) {
                              await saveDefaultSessionMinutes(60);
                            }
                            if (!mounted) return;
                            setSheetState(() {
                              selectedBudget = 60;
                              isCustom = false;
                              step = 1;
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('2 hours'),
                          selected: selectedBudget == 120 && !isCustom,
                          onSelected: (_) async {
                            if (rememberAsDefault) {
                              await saveDefaultSessionMinutes(120);
                            }
                            if (!mounted) return;
                            setSheetState(() {
                              selectedBudget = 120;
                              isCustom = false;
                              step = 1;
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Custom'),
                          selected: isCustom,
                          onSelected: (_) {
                            setSheetState(() {
                              isCustom = true;
                            });
                          },
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Remember as my default'),
                      value: rememberAsDefault,
                      onChanged: (value) {
                        setSheetState(() {
                          rememberAsDefault = value ?? false;
                        });
                      },
                    ),
                    if (isCustom) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: customController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minutes',
                          suffixText: 'min',
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: () async {
                          final customMinutes = int.tryParse(
                            customController.text.trim(),
                          );
                          if (customMinutes == null || customMinutes <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter a valid minute budget.'),
                              ),
                            );
                            return;
                          }
                          if (rememberAsDefault) {
                            await saveDefaultSessionMinutes(customMinutes);
                          }
                          if (!mounted) return;
                          setSheetState(() {
                            selectedBudget = customMinutes;
                            step = 1;
                          });
                        },
                        child: const Text('Continue'),
                      ),
                    ],
                  ] else if (step == 1) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(activeDriveArea?.name ?? 'No active area'),
                      subtitle: Text(activeDriveArea?.city ?? 'Pick an area'),
                      trailing: TextButton(
                        onPressed: () {
                          setSheetState(() {
                            showAreaList = !showAreaList;
                          });
                        },
                        child: const Text('Change'),
                      ),
                    ),
                    if (showAreaList)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView(
                          shrinkWrap: true,
                          children: driveAreas
                              .map(
                                (area) => ListTile(
                                  title: Text(area.name),
                                  subtitle: Text(area.city),
                                  onTap: () async {
                                    await setActiveDriveArea(area);
                                    if (!mounted) return;
                                    setSheetState(() {
                                      showAreaList = false;
                                    });
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: activeDriveArea == null
                          ? null
                          : () => setSheetState(() => step = 2),
                      child: const Text('Continue'),
                    ),
                  ] else ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    activeDriveArea?.name ?? 'Mission',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${areaCoveragePercent.toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: areaCoveragePercent / 100,
                              minHeight: 4,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              previewTitle,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              previewHelper,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(label: Text(availableTimeLabel)),
                                Chip(
                                  label: Text(
                                    '${previewStreets.length} streets selected',
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    '${missionRemainingCoveragePercent.toStringAsFixed(0)}% coverage gain',
                                  ),
                                ),
                              ],
                            ),
                            if (!noTimeFit &&
                                !noMarketMapForArea &&
                                hasAreaStreetData &&
                                previewStreets.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                '~$sessionsToFinish more sessions to finish this area.',
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                            if (!hasAreaStreetData || noMarketMapForArea) ...[
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                icon: const Icon(Icons.analytics),
                                label: Text(
                                  isBuildingMarketMap
                                      ? 'Analyzing area...'
                                      : motivatedSellersButtonLabel,
                                ),
                                onPressed:
                                    isBuildingMarketMap ||
                                        activeDriveArea == null
                                    ? null
                                    : () async {
                                        await buildMarketMap();
                                        if (!sheetContext.mounted) return;
                                        setSheetState(() {});
                                      },
                              ),
                              const SizedBox(height: 4),
                              const _MotivatedSellersDescription(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (noTimeFit) ...[
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            rememberAsDefault = false;
                            isCustom = false;
                            step = 0;
                          });
                        },
                        child: const Text('Change time'),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.route),
                        label: const Text('Start default mission'),
                        onPressed: isSavingMission || activeDriveArea == null
                            ? null
                            : () async {
                                Navigator.pop(sheetContext);
                                await generateMission(
                                  currentStreetOpportunities,
                                  includeUnscored:
                                      includeUnscoredMissionStreets,
                                );
                              },
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Use best available streets anyway'),
                        onPressed:
                            isSavingMission ||
                                activeDriveArea == null ||
                                forcedBestAvailableStreets.isEmpty
                            ? null
                            : () async {
                                Navigator.pop(sheetContext);
                                setState(() {
                                  selectedMissionTimeBudgetMinutes =
                                      selectedBudget;
                                });
                                await generateMission(
                                  currentStreetOpportunities,
                                  timeBudgetMinutes: selectedBudget,
                                  includeUnscored:
                                      includeUnscoredMissionStreets,
                                  forceAtLeastOne: true,
                                );
                              },
                      ),
                    ] else ...[
                      FilledButton.icon(
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Start Driving ->'),
                        onPressed:
                            previewStreets.isEmpty ||
                                isSavingMission ||
                                activeDriveArea == null
                            ? null
                            : () async {
                                Navigator.pop(sheetContext);
                                setState(() {
                                  selectedMissionTimeBudgetMinutes =
                                      selectedBudget;
                                });
                                await generateMission(
                                  currentStreetOpportunities,
                                  timeBudgetMinutes: timeMissionsEnabled
                                      ? selectedBudget
                                      : null,
                                  includeUnscored:
                                      includeUnscoredMissionStreets,
                                );
                              },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (timeMissionsEnabled)
                            TextButton(
                              onPressed: () {
                                setSheetState(() {
                                  rememberAsDefault = false;
                                  isCustom = false;
                                  step = 0;
                                });
                              },
                              child: const Text('Change time'),
                            ),
                          if (timeMissionsEnabled)
                            const Text(
                              '-',
                              style: TextStyle(color: Color(0xFF6B7280)),
                            ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              openWeeklyPlannerSheet(
                                currentStreetOpportunities,
                              );
                            },
                            child: const Text('Plan my week'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(customController.dispose);
  }

  void openMissionDetailSheet({
    required int missionCoveredCount,
    required int missionStreetTotal,
    required StreetOpportunity? nextMissionStreet,
    required int missionEstimatedMinutesRemaining,
    required double missionOpportunityRemaining,
    required int missionLeadsFound,
    required double missionMiles,
    required double missionOpportunityCaptured,
    required bool hasMissionOpportunityScore,
  }) {
    final mission = activeMission;
    if (mission == null) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                activeDriveArea?.name ?? 'Mission',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value:
                    (safePercent(missionCoveredCount, missionStreetTotal) / 100)
                        .clamp(0, 1),
              ),
              const SizedBox(height: 12),
              Text(
                '$missionCoveredCount of $missionStreetTotal streets - ${missionEstimatedMinutesRemaining}m left',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                nextMissionStreet == null
                    ? 'Mission streets complete'
                    : 'Next: ${nextMissionStreet.street.streetName.isEmpty ? 'Unnamed street' : nextMissionStreet.street.streetName}',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text('$missionLeadsFound leads')),
                  Chip(label: Text('${missionMiles.toStringAsFixed(2)} mi')),
                  if (hasMissionOpportunityScore)
                    Chip(
                      label: Text(
                        '${missionOpportunityRemaining.toStringAsFixed(0)} opp left',
                      ),
                    ),
                ],
              ),
              if (mission.missionStartPoint != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.alt_route),
                  label: const Text('Route to Start'),
                  onPressed: () {
                    Navigator.pop(context);
                    unawaited(showRouteToMissionStart());
                  },
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show only active area'),
                value: showOnlyActiveArea,
                onChanged: (value) {
                  setState(() {
                    showOnlyActiveArea = value;
                  });
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    icon: Icon(
                      isTracking ? Icons.navigation : Icons.play_arrow,
                    ),
                    label: Text(isTracking ? 'Driving' : 'Start Driving'),
                    onPressed: isTracking ? null : startMissionDriving,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                    onPressed: pauseMission,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Complete'),
                    onPressed: () => completeMission(
                      streetsCovered: missionCoveredCount,
                      opportunityCaptured: missionOpportunityCaptured,
                      leadsFound: missionLeadsFound,
                      milesDriven: missionMiles,
                      closeContext: context,
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Time-based missions'),
                value: timeMissionsEnabled,
                onChanged: (value) async {
                  await saveTimeMissionsEnabled(value);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  ({double west, double south, double east, double north})? polygonBounds(
    List<LatLng> polygon,
  ) {
    if (polygon.isEmpty) return null;

    var west = polygon.first.longitude;
    var east = polygon.first.longitude;
    var south = polygon.first.latitude;
    var north = polygon.first.latitude;

    for (final point in polygon.skip(1)) {
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
    }

    return (west: west, south: south, east: east, north: north);
  }

  String marketPropertyKey(ParcelProperty parcel) {
    return parcel.accountNo ??
        parcel.parcelNo ??
        '${parcel.centroid?.latitude.toStringAsFixed(7)},${parcel.centroid?.longitude.toStringAsFixed(7)},${parcel.displayAddress}';
  }

  String portfolioOwnerKey(ParcelProperty parcel) {
    final ownerKey = normalizedAddressKey(parcel.ownerName);
    final mailingKey = normalizedAddressKey(parcel.mailingAddress);

    return '$ownerKey|$mailingKey';
  }

  bool isAbsenteeOwner(ParcelProperty parcel) {
    final propertyKey = normalizedAddressKey(parcel.propertyAddress);
    final mailingKey = normalizedAddressKey(parcel.mailingAddress);

    return propertyKey.isNotEmpty &&
        mailingKey.isNotEmpty &&
        propertyKey != mailingKey;
  }

  bool isLowImprovementRatio(ParcelProperty parcel) {
    final improvement = parcel.improvementValue;

    if (improvement == null) return false;

    final land = parcel.landValue;
    if (land != null && land > 0 && improvement / land < 0.35) return true;

    final assessed = parcel.assessedValue;
    if (assessed != null && assessed > 0 && improvement / assessed < 0.25) {
      return true;
    }

    return false;
  }

  bool isLongHeld(ParcelProperty parcel) {
    final yearsOwned = yearsOwnedFromSaleDate(parcel.saleDate, DateTime.now());

    return yearsOwned != null && yearsOwned >= 15;
  }

  bool isOlderBuild(ParcelProperty parcel) {
    final yearBuilt = parcel.yearBuilt;

    return yearBuilt != null && yearBuilt > 0 && yearBuilt < 1985;
  }

  Map<String, dynamic> marketSignalsForParcel(
    ParcelProperty parcel,
    int portfolioCount,
  ) {
    return {
      'out_of_state': parcel.outOfStateOwner,
      'absentee': isAbsenteeOwner(parcel),
      'portfolio_count': portfolioCount,
      'low_improvement_ratio': isLowImprovementRatio(parcel),
      'long_held': isLongHeld(parcel),
      'older_build': isOlderBuild(parcel),
      'year_built_threshold': 1985,
      'long_held_years_threshold': 15,
    };
  }

  Future<void> scoreStoredMarketProperties(
    List<MarketProperty> properties,
  ) async {
    final unscoredRows = properties
        .where((property) => !property.hasStoredScore)
        .map((property) {
          final result = targetScoreForSignals(property.signals);

          return {
            'id': property.id,
            'account_id': widget.activeAccountId,
            'target_score': result.score,
            'score_breakdown': result.breakdown,
            'score_version': targetScoreVersion,
            'scored_at': DateTime.now().toUtc().toIso8601String(),
          };
        })
        .toList(growable: false);

    if (unscoredRows.isEmpty) return;

    try {
      await supabase.from('properties').upsert(unscoredRows);
      await loadMarketProperties();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not score market properties.')),
      );
    }
  }

  Map<String, dynamic> marketPropertyRow(
    DriveArea area,
    ParcelProperty parcel,
    int portfolioCount,
  ) {
    final centroid = parcel.centroid;
    final signals = marketSignalsForParcel(parcel, portfolioCount);
    final scoreResult = targetScoreForSignals(signals);

    return {
      'account_id': widget.activeAccountId,
      'created_by': supabase.auth.currentUser?.id,
      'account_no': marketPropertyKey(parcel),
      'drive_area_id': area.id,
      'address': parcel.propertyAddress,
      'owner_name': parcel.ownerName,
      'mailing_address': parcel.mailingAddress,
      'mailing_state': parcel.mailingState,
      'out_of_state': signals['out_of_state'],
      'absentee': signals['absentee'],
      'property_type': parcel.propertyType,
      'year_built': parcel.yearBuilt,
      'square_feet': parcel.squareFeet,
      'lot_acres': parcel.lotAcres,
      'assessed_value': parcel.assessedValue,
      'land_value': parcel.landValue,
      'improvement_value': parcel.improvementValue,
      'last_sale_date': parcel.saleDate,
      'last_sale_price': parcel.salePrice,
      'latitude': centroid?.latitude,
      'longitude': centroid?.longitude,
      'rings': parcelRingsToJson(parcel.rings),
      'signals': signals,
      'target_score': scoreResult.score,
      'score_breakdown': scoreResult.breakdown,
      'score_version': targetScoreVersion,
      'scored_at': DateTime.now().toUtc().toIso8601String(),
      'refreshed_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<void> buildMarketMap() async {
    final area = activeDriveArea;
    final bounds = area == null ? null : polygonBounds(area.polygon);

    if (area == null || bounds == null || isBuildingMarketMap) return;

    setState(() {
      isBuildingMarketMap = true;
      marketMapFetchedCount = 0;
      marketMapSavedCount = 0;
      marketMapMessage = 'Fetching parcels inside ${area.name}...';
    });

    try {
      final parcelsByAccount = <String, ParcelProperty>{};
      var hitPageLimit = false;

      for (
        var pageIndex = 0;
        pageIndex < marketMapMaxParcelPages;
        pageIndex++
      ) {
        final offset = pageIndex * visibleParcelLimit;
        final page = await fetchParcelsByLatLongBox(
          west: bounds.west,
          south: bounds.south,
          east: bounds.east,
          north: bounds.north,
          resultRecordCount: visibleParcelLimit,
          returnGeometry: true,
          resultOffset: offset,
        ).timeout(marketMapParcelPageTimeout);

        var newParcelCount = 0;
        for (final parcel in page) {
          final centroid = parcel.centroid;

          if (centroid == null || !pointInRing(centroid, area.polygon)) {
            continue;
          }

          final key = marketPropertyKey(parcel);
          if (!parcelsByAccount.containsKey(key)) {
            newParcelCount++;
          }
          parcelsByAccount[key] = parcel;
        }

        if (!mounted) return;

        setState(() {
          marketMapFetchedCount = parcelsByAccount.length;
          marketMapMessage =
              'Fetched $marketMapFetchedCount parcels inside the area... '
              '(page ${pageIndex + 1})';
        });

        if (page.length < visibleParcelLimit) break;
        if (newParcelCount == 0) break;
        if (pageIndex == marketMapMaxParcelPages - 1) {
          hitPageLimit = true;
        }
      }

      if (hitPageLimit) {
        if (!mounted) return;

        setState(() {
          isBuildingMarketMap = false;
          marketMapMessage =
              'This area is too large to analyze at once. Draw a smaller Drive Area and try again.';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This area is too large to analyze at once. Draw a smaller Drive Area and try again.',
            ),
          ),
        );
        return;
      }

      final portfolioCounts = <String, int>{};
      for (final parcel in parcelsByAccount.values) {
        final key = portfolioOwnerKey(parcel);
        if (key == '|') continue;

        portfolioCounts[key] = (portfolioCounts[key] ?? 0) + 1;
      }

      final rows = parcelsByAccount.values
          .map(
            (parcel) => marketPropertyRow(
              area,
              parcel,
              portfolioCounts[portfolioOwnerKey(parcel)] ?? 1,
            ),
          )
          .toList(growable: false);

      const batchSize = 100;
      for (var index = 0; index < rows.length; index += batchSize) {
        final end = math.min(index + batchSize, rows.length);
        await supabase
            .from('properties')
            .upsert(
              rows.sublist(index, end),
              onConflict: 'account_no,drive_area_id',
            );

        if (!mounted) return;

        setState(() {
          marketMapSavedCount = end;
          marketMapMessage = 'Saved $marketMapSavedCount of ${rows.length}...';
        });
      }

      await loadMarketProperties();

      if (!mounted) return;

      setState(() {
        isBuildingMarketMap = false;
        marketMapMessage = 'Area analyzed: ${rows.length} homes loaded.';
      });

      focusMapWorkspace(
        mode: 'targets',
        point: polygonCenter(area.polygon),
        minZoom: 15,
        message: 'Targets map ready for ${area.name}.',
      );
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        isBuildingMarketMap = false;
        marketMapMessage =
            'Parcel service timed out. Try again, or draw a smaller Drive Area.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Parcel service timed out. Try again, or draw a smaller Drive Area.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isBuildingMarketMap = false;
        marketMapMessage = 'Could not analyze area. Try a smaller area.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not analyze area. Try a smaller area.'),
        ),
      );
    }
  }

  LatLng? polygonCenter(List<LatLng> polygon) {
    if (polygon.isEmpty) return null;

    var latitude = 0.0;
    var longitude = 0.0;

    for (final point in polygon) {
      latitude += point.latitude;
      longitude += point.longitude;
    }

    return LatLng(latitude / polygon.length, longitude / polygon.length);
  }

  LatLng? streetFocusPoint(CityStreet street) {
    if (street.path.isEmpty) return null;

    return street.path[street.path.length ~/ 2];
  }

  void focusMapWorkspace({
    required String mode,
    LatLng? point,
    double minZoom = 16,
    String? message,
  }) {
    if (!mounted) return;

    setState(() {
      mapMode = mode;
      if (message != null) {
        locationMessage = message;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final mapContext = mapWorkspaceKey.currentContext;
      if (mapContext != null) {
        Scrollable.ensureVisible(
          mapContext,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
      }

      if (mapIsReady && point != null) {
        mapController.move(point, math.max(currentZoom, minZoom));
      }
    });
  }

  void focusStreetWorkspace(String mode, CityStreet street, {String? message}) {
    focusMapWorkspace(
      mode: mode,
      point: streetFocusPoint(street),
      minZoom: 17,
      message: message,
    );
  }

  void handleMapPositionChanged(MapCamera camera, bool hasGesture) {
    final wasShowingHouseNumbers = currentZoom >= houseNumberLabelZoom;
    final isShowingHouseNumbers = camera.zoom >= houseNumberLabelZoom;
    final shouldDisableFollow = hasGesture && followMyLocation;

    if (wasShowingHouseNumbers != isShowingHouseNumbers ||
        shouldDisableFollow) {
      setState(() {
        currentMapCenter = camera.center;
        currentZoom = camera.zoom;
        if (shouldDisableFollow) {
          followMyLocation = false;
          locationMessage = 'Follow mode off. Tap Find Me to recenter.';
        }
      });
    } else {
      currentMapCenter = camera.center;
      currentZoom = camera.zoom;
    }

    if (shouldDisableFollow) {
      unawaited(
        FieldTestLogger.log('gps_follow_disabled', detail: 'manual map move'),
      );
    }

    scheduleVisibleParcelLoad();
    scheduleVisibleStreetLoad();
  }

  Widget buildFindMeFab() {
    return FloatingActionButton.extended(
      heroTag: 'drive-center-me',
      backgroundColor: followMyLocation
          ? const Color(0xFF2563EB)
          : Colors.white,
      foregroundColor: followMyLocation
          ? Colors.white
          : const Color(0xFF111827),
      tooltip: followMyLocation ? 'Following Your Location' : 'Center On Me',
      onPressed: isFindingLocation ? null : () => unawaited(findMyLocation()),
      icon: isFindingLocation
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: followMyLocation ? Colors.white : null,
              ),
            )
          : Icon(followMyLocation ? Icons.gps_fixed : Icons.my_location),
      label: Text(
        isFindingLocation
            ? 'Finding'
            : followMyLocation
            ? 'Following'
            : 'Find Me',
      ),
    );
  }

  bool hasUsableHeading(Position? position) {
    final heading = position?.heading;
    return heading != null && heading.isFinite && heading >= 0;
  }

  Widget buildUserLocationMarker() {
    final heading = lastKnownPosition?.heading ?? 0;
    final markerCore = hasUsableHeading(lastKnownPosition)
        ? Transform.rotate(
            angle: heading * math.pi / 180,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: const Icon(
                Icons.navigation,
                color: Colors.white,
                size: 14,
              ),
            ),
          )
        : Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          );

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Color(0x332196F3),
            shape: BoxShape.circle,
          ),
        ),
        markerCore,
      ],
    );
  }

  Widget buildLocationStatusPill() {
    final icon = isFindingLocation
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            followMyLocation ? Icons.gps_fixed : Icons.location_searching,
            size: 18,
            color: followMyLocation
                ? const Color(0xFF2563EB)
                : const Color(0xFF374151),
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              locationMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> showRouteToMissionStart() async {
    final startPoint = activeMission?.missionStartPoint;
    if (startPoint == null) return;

    if (myLocation == null) {
      final found = await findMyLocation(reason: 'route_to_start');
      if (!found || myLocation == null) return;
    }

    if (!mounted) return;

    // TODO(routing): replace this straight-line preview with OSRM, Valhalla,
    // or GraphHopper turn-by-turn routing when the routing engine is selected.
    setState(() {
      showRouteToStartLine = true;
      locationMessage =
          'Route to Start preview shown. Full routing engine is not connected yet.';
    });

    final current = myLocation!;
    final midpoint = LatLng(
      (current.latitude + startPoint.latitude) / 2,
      (current.longitude + startPoint.longitude) / 2,
    );
    if (mapIsReady) {
      mapController.move(midpoint, math.max(currentZoom, 14));
    }
    unawaited(FieldTestLogger.log('route_to_start_preview'));
  }

  Future<void> startAreaDrive() async {
    final area = activeDriveArea;
    if (area == null) return;

    final center = polygonCenter(area.polygon);
    focusMapWorkspace(
      mode: 'drive',
      point: center,
      minZoom: 15,
      message: 'Area drive map ready: ${area.name}.',
    );

    if (isTracking) {
      setState(() {
        locationMessage = 'Area drive already running: ${area.name}.';
      });
      return;
    }

    await startTracking();

    if (!mounted) return;

    setState(() {
      locationMessage = 'Area drive started: ${area.name}.';
    });
  }

  void enterDrawAreaMode() {
    setState(() {
      isDrawAreaMode = true;
      showSavedAreasWhileDrawing = false;
      selectedParcel = null;
      mapMode = 'drive';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tap the map to draw your area boundary.')),
    );
  }

  void setShowOnlyActiveArea(bool value) {
    setState(() {
      showOnlyActiveArea = value;
    });
  }

  void setTargetFilter(String filter, bool value) {
    setState(() {
      switch (filter) {
        case 'out_of_state':
          targetFilterOutOfState = value;
        case 'absentee':
          targetFilterAbsentee = value;
        case 'portfolio':
          targetFilterPortfolio = value;
        case 'low_improvement':
          targetFilterLowImprovement = value;
      }
    });
  }

  List<CityStreet> streetsInsideArea(DriveArea area) {
    if (area.polygon.length < 3) return const <CityStreet>[];

    return cityStreets
        .where(
          (street) =>
              street.path.any((point) => pointInRing(point, area.polygon)),
        )
        .toList(growable: false);
  }

  void focusNextUncoveredStreet(List<CityStreet> activeAreaUncoveredStreets) {
    if (activeDriveArea == null) return;

    if (activeAreaUncoveredStreets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No uncovered streets in this area.')),
      );
      return;
    }

    final origin = myLocation ?? currentMapCenter;
    CityStreet? nearestStreet;
    var nearestDistance = double.infinity;

    for (final street in activeAreaUncoveredStreets) {
      final distance = distanceToStreetMiles(origin, street);

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestStreet = street;
      }
    }

    final focusPoint = nearestStreet == null
        ? null
        : streetFocusPoint(nearestStreet);

    if (focusPoint == null) return;

    focusMapWorkspace(
      mode: 'coverage',
      point: focusPoint,
      minZoom: 17,
      message: nearestStreet!.streetName.isEmpty
          ? 'Centered on the next uncovered street.'
          : 'Next uncovered street: ${nearestStreet.streetName}.',
    );
  }

  bool marketPropertyPassesTargetFilters(MarketProperty property) {
    if (targetFilterOutOfState && !property.outOfState) return false;
    if (targetFilterAbsentee && !property.absentee) return false;
    if (targetFilterPortfolio && property.portfolioCount < 3) return false;
    if (targetFilterLowImprovement && !property.lowImprovementRatio) {
      return false;
    }

    return true;
  }

  MarketProperty? marketPropertyForParcel(ParcelProperty parcel) {
    final parcelKey = marketPropertyKey(parcel);

    for (final property in marketProperties) {
      if (marketPropertyKey(property.parcel) == parcelKey) return property;
    }

    return null;
  }

  Widget targetScoreBadge(
    double score, {
    double fontSize = 13,
    VoidCallback? onTap,
  }) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: targetScoreColor(score),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        score.toStringAsFixed(0),
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    if (onTap == null) return badge;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: badge,
    );
  }

  List<StreetOpportunity> streetOpportunitiesFor(
    List<CityStreet> streets,
    List<MarketProperty> properties,
  ) {
    final propertyPoints = <({LatLng point, double score})>[];

    for (final property in properties) {
      final centroid = property.parcel.centroid;
      if (centroid == null) continue;

      propertyPoints.add((point: centroid, score: property.targetScore));
    }

    final opportunities = streets.map((street) {
      final isCovered = coveredStreetIds.contains(street.id);
      var score = 0.0;

      if (!isCovered) {
        final bounds = latLngBounds(street.path);

        if (bounds != null) {
          for (final property in propertyPoints) {
            if (!pointNearLatLngBounds(
              property.point,
              bounds,
              opportunityStreetMatchMiles,
            )) {
              continue;
            }

            if (distanceToStreetMiles(property.point, street) <=
                opportunityStreetMatchMiles) {
              score += property.score;
            }
          }
        }
      }

      return StreetOpportunity(
        street: street,
        score: score,
        isCovered: isCovered,
      );
    }).toList();

    opportunities.sort((a, b) => b.score.compareTo(a.score));

    return opportunities;
  }

  List<StreetOpportunity> cachedStreetOpportunitiesForActiveArea(
    List<CityStreet> streets,
    List<MarketProperty> properties,
  ) {
    final area = activeDriveArea;
    if (area == null) return const <StreetOpportunity>[];

    final coveredCount = coveredStreetIds.length;
    if (cachedStreetOpportunityAreaId == area.id &&
        cachedStreetOpportunityStreetCount == streets.length &&
        cachedStreetOpportunityPropertyCount == properties.length &&
        cachedStreetOpportunityCoveredCount == coveredCount) {
      return cachedStreetOpportunities;
    }

    final opportunities = streetOpportunitiesFor(streets, properties);
    cachedStreetOpportunities = opportunities;
    cachedStreetOpportunityAreaId = area.id;
    cachedStreetOpportunityStreetCount = streets.length;
    cachedStreetOpportunityPropertyCount = properties.length;
    cachedStreetOpportunityCoveredCount = coveredCount;

    return opportunities;
  }

  void clearStreetOpportunityCache() {
    cachedStreetOpportunities = const [];
    cachedStreetOpportunityAreaId = null;
    cachedStreetOpportunityStreetCount = -1;
    cachedStreetOpportunityPropertyCount = -1;
    cachedStreetOpportunityCoveredCount = -1;
  }

  Color streetOpportunityColor(StreetOpportunity opportunity) {
    if (opportunity.isCovered) return const Color(0x555F6368);
    if (opportunity.score >= 220) return const Color(0xFFE53935);
    if (opportunity.score >= 120) return const Color(0xFFFF9800);
    if (opportunity.score > 0) return const Color(0xFFFDD835);
    return const Color(0x66757575);
  }

  void showTargetScoreBreakdown(MarketProperty property) {
    final contributions =
        (property.scoreBreakdown['contributions'] as List?) ?? const [];

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Target Score ${property.targetScore.toStringAsFixed(0)}',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(property.parcel.displayAddress),
                  const SizedBox(height: 12),
                  ...contributions.whereType<Map>().map((item) {
                    final label = item['label']?.toString() ?? 'Signal';
                    final applies = item['applies'] == true;
                    final points = ((item['points'] ?? 0) as num).toDouble();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            applies
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            size: 18,
                            color: applies
                                ? targetScoreColor(points)
                                : const Color(0xFF757575),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(label)),
                          Text('+${points.toStringAsFixed(0)}'),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  StreetOpportunity? chooseNextMissionStreet(
    List<StreetOpportunity> uncoveredMissionOpportunities,
  ) {
    if (uncoveredMissionOpportunities.isEmpty) return null;

    final origin = myLocation ?? currentMapCenter;
    final ranked = [...uncoveredMissionOpportunities];

    ranked.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;

      return distanceToStreetMiles(
        origin,
        a.street,
      ).compareTo(distanceToStreetMiles(origin, b.street));
    });

    return ranked.first;
  }

  List<Lead> leadsForMission(Mission? mission) {
    if (mission == null) return [];

    return missionLeadsById[mission.id] ?? [];
  }

  int leadsFoundDuringMission(Mission? mission) {
    return leadsForMission(mission).length;
  }

  double milesForMission(Mission mission) {
    final driveSessionId = mission.driveSessionId;
    if (driveSessionId == null || driveSessionId.isEmpty) return 0;

    return drivingPointMiles(
      savedDrivingPoints
          .where((point) => point.driveSessionId == driveSessionId)
          .toList(growable: false),
    );
  }

  int coveredStreetCountForMission(Mission mission) {
    return missionCoveredStreetCount(mission, coveredStreetIds);
  }

  void handleMapTap(LatLng point) {
    if (isDrawAreaMode) {
      setState(() {
        selectedParcel = null;
        drawingAreaPoints = [...drawingAreaPoints, point];
      });
      return;
    }

    selectParcelAt(point);
  }

  void clearDrawingArea() {
    setState(() {
      drawingAreaPoints = [];
    });
  }

  void undoLastDrawingPoint() {
    if (drawingAreaPoints.isEmpty) return;

    setState(() {
      drawingAreaPoints = drawingAreaPoints.sublist(
        0,
        drawingAreaPoints.length - 1,
      );
    });
  }

  void cancelDrawAreaMode() {
    setState(() {
      isDrawAreaMode = false;
      drawingAreaPoints = [];
    });
  }

  Future<String?> promptForDriveAreaName() {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => const AreaNameDialog(),
    );
  }

  Future<String?> promptForDrawnAreaAction() {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Analyze this area?',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "We'll load the streets, homes, parcels, your saved leads, and target opportunities inside this area.",
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  icon: const Icon(Icons.analytics),
                  label: const Text('Analyze'),
                  onPressed: () => Navigator.pop(sheetContext, 'analyze'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_location_alt),
                  label: const Text('Adjust'),
                  onPressed: () => Navigator.pop(sheetContext, 'adjust'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, 'cancel'),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> saveDrawingArea() async {
    if (drawingAreaPoints.length < 3 || isSavingDriveArea) return;

    final name = await promptForDriveAreaName();
    if (!mounted) return;
    if (name == null || name.isEmpty) return;

    final action = await promptForDrawnAreaAction();
    if (!mounted) return;
    if (action == null || action == 'adjust') return;
    if (action == 'cancel') {
      cancelDrawAreaMode();
      return;
    }

    setState(() {
      isSavingDriveArea = true;
    });

    try {
      await supabase
          .from('drive_areas')
          .update({'is_active': false})
          .eq('account_id', widget.activeAccountId)
          .eq('is_active', true);
      final inserted = await supabase
          .from('drive_areas')
          .insert({
            'account_id': widget.activeAccountId,
            'created_by': supabase.auth.currentUser?.id,
            'name': name,
            'city': selectedCoverageCity,
            'polygon': driveAreaPolygonToJson(drawingAreaPoints),
            'status': 'in_progress',
            'is_active': true,
          })
          .select()
          .single();
      final newArea = DriveArea.fromMap(inserted);

      if (!mounted) return;

      setState(() {
        isDrawAreaMode = false;
        drawingAreaPoints = [];
        isSavingDriveArea = false;
      });

      await loadDriveAreas();
      await buildMarketMap();
      if (!mounted) return;

      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => _AreaDetailScreen(
            driveStateProvider: () => mounted ? this : null,
            initialArea: newArea,
            onOpenDrive: () {},
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isSavingDriveArea = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save drive area.')),
      );
    }
  }

  Widget drawAreaMobileActionBar() {
    final canSave = drawingAreaPoints.length >= 3 && !isSavingDriveArea;
    final helperText = drawingAreaPoints.length < 3
        ? 'Add at least 3 points.'
        : '${drawingAreaPoints.length} points ready.';

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                helperText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.undo),
                      label: const Text('Undo'),
                      onPressed: drawingAreaPoints.isEmpty
                          ? null
                          : undoLastDrawingPoint,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear'),
                      onPressed: drawingAreaPoints.isEmpty
                          ? null
                          : clearDrawingArea,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: isSavingDriveArea ? null : cancelDrawAreaMode,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: Text(
                        isSavingDriveArea ? 'Saving...' : 'Save Area',
                      ),
                      onPressed: canSave ? saveDrawingArea : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> changeCoverageCity(String city) async {
    await MarketService.setActiveCity(city);
    final prefs = await SharedPreferences.getInstance();
    final updatedRecentMarkets = [
      city,
      ...recentMarketCities.where((recentCity) => recentCity != city),
    ].take(8).toList(growable: false);
    await prefs.setStringList(recentMarketCitiesPrefsKey, updatedRecentMarkets);

    setState(() {
      selectedCoverageCity = city;
      recentMarketCities = updatedRecentMarkets;
      cityStreets = [];
      coveredStreetIds = {};
      totalCityStreetCount = 0;
      clearStreetOpportunityCache();
    });

    await loadStreetCoverage();
    await loadCityReadiness(forceRefresh: true);
  }

  Future<void> openMarketPicker() async {
    final markets = cityReadiness.isEmpty
        ? await loadCityReadiness(forceRefresh: true)
        : cityReadiness;
    if (!mounted) return;

    final selectedMarket = await Navigator.push<CityReadiness>(
      context,
      MaterialPageRoute(
        builder: (_) => _MarketPickerScreen(
          cities: markets,
          activeCity: selectedCoverageCity,
          recentMarkets: recentMarketCities,
        ),
      ),
    );
    if (selectedMarket == null || !mounted) return;

    await changeCoverageCity(selectedMarket.cityName);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Active market set to ${selectedMarket.displayName}'),
      ),
    );
  }

  void scheduleVisibleStreetLoad() {
    visibleStreetLoadTimer?.cancel();
    visibleStreetLoadTimer = Timer(
      const Duration(milliseconds: 500),
      loadVisibleCityStreets,
    );
  }

  Future<void> loadVisibleCityStreets() async {
    if (!mounted || !mapIsReady || isLoadingVisibleStreets) return;

    setState(() {
      isLoadingVisibleStreets = true;
    });

    try {
      final bounds = mapController.camera.visibleBounds;
      final streetData = await supabase
          .from('city_streets')
          .select('id,city,street_name,path')
          .eq('city', selectedCoverageCity)
          .lte('min_lat', bounds.north)
          .gte('max_lat', bounds.south)
          .lte('min_lng', bounds.east)
          .gte('max_lng', bounds.west)
          .limit(visibleStreetLimit);
      final streets = streetData
          .map<CityStreet>((item) => CityStreet.fromMap(item))
          .where((street) => street.path.length > 1)
          .toList();

      if (!mounted) return;

      setState(() {
        cityStreets = streets;
        clearStreetOpportunityCache();
        isLoadingVisibleStreets = false;
      });

      await syncSavedDrivingPointsToStreetCoverage();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoadingVisibleStreets = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load visible streets.')),
      );
    }
  }

  List<CityStreet> findNearbyUncoveredStreets(Iterable<LatLng> points) {
    final newlyCoveredStreets = <String, CityStreet>{};
    final streetBounds = cityStreets
        .map((street) => (street: street, bounds: latLngBounds(street.path)))
        .where((entry) => entry.bounds != null)
        .toList(growable: false);

    for (final point in points) {
      for (final entry in streetBounds) {
        final street = entry.street;
        if (coveredStreetIds.contains(street.id) ||
            newlyCoveredStreets.containsKey(street.id)) {
          continue;
        }

        final bounds = entry.bounds;
        if (bounds == null ||
            !pointNearLatLngBounds(point, bounds, streetCoverageMatchMiles)) {
          continue;
        }

        if (distanceToStreetMiles(point, street) <= streetCoverageMatchMiles) {
          newlyCoveredStreets[street.id] = street;
        }
      }
    }

    return newlyCoveredStreets.values.toList(growable: false);
  }

  Future<void> saveStreetCoverage(
    List<CityStreet> streets,
    String? driveSessionId,
  ) async {
    if (streets.isEmpty) return;

    final userId = supabase.auth.currentUser?.id;
    final rows = streets
        .map(
          (street) => {
            'street_id': street.id,
            'city': street.city.isEmpty ? selectedCoverageCity : street.city,
            'drive_session_id': driveSessionId,
            'user_id': userId,
            'account_id': widget.activeAccountId,
            'created_by': userId,
          },
        )
        .toList();

    await supabase
        .from('street_coverage')
        .upsert(rows, onConflict: 'user_id,street_id');
  }

  Future<void> markNearbyStreetsCovered(
    LatLng point,
    String? driveSessionId,
  ) async {
    final newlyCoveredStreets = findNearbyUncoveredStreets([point]);

    if (newlyCoveredStreets.isEmpty) return;

    if (mounted) {
      setState(() {
        coveredStreetIds = {
          ...coveredStreetIds,
          ...newlyCoveredStreets.map((street) => street.id),
        };
        clearStreetOpportunityCache();
      });
    }

    try {
      await saveStreetCoverage(newlyCoveredStreets, driveSessionId);
      for (final street in newlyCoveredStreets) {
        unawaited(FieldTestLogger.log('street_covered', detail: street.id));
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save street coverage.')),
      );
    }
  }

  Future<void> syncSavedDrivingPointsToStreetCoverage() async {
    if (isSyncingStreetCoverage ||
        isTracking ||
        cityStreets.isEmpty ||
        savedDrivingPoints.isEmpty) {
      return;
    }

    isSyncingStreetCoverage = true;

    try {
      final newlyCoveredStreets = findNearbyUncoveredStreets(
        savedDrivingPoints.map((drivingPoint) => drivingPoint.point),
      );

      if (newlyCoveredStreets.isEmpty) return;

      if (mounted) {
        setState(() {
          coveredStreetIds = {
            ...coveredStreetIds,
            ...newlyCoveredStreets.map((street) => street.id),
          };
          clearStreetOpportunityCache();
        });
      }

      await saveStreetCoverage(newlyCoveredStreets, null);
      for (final street in newlyCoveredStreets) {
        unawaited(FieldTestLogger.log('street_covered', detail: street.id));
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save street coverage.')),
      );
    } finally {
      isSyncingStreetCoverage = false;
    }
  }

  Future<ParcelProperty?> fetchParcelAtPoint(LatLng point) async {
    final parcels = await fetchParcelsFromArcGis(
      {
        'geometry': jsonEncode({
          'x': point.longitude,
          'y': point.latitude,
          'spatialReference': {'wkid': 4326},
        }),
        'geometryType': 'esriGeometryPoint',
      },
      resultRecordCount: 5,
      returnGeometry: true,
    );

    return nearestParcel(point, parcels);
  }

  Future<ParcelProperty?> fetchParcelNearPoint(LatLng point) async {
    const tapBuffer = 0.0008;
    var parcels = await fetchParcelsFromArcGis(
      {
        'geometry':
            '${point.longitude - tapBuffer},${point.latitude - tapBuffer},${point.longitude + tapBuffer},${point.latitude + tapBuffer}',
        'geometryType': 'esriGeometryEnvelope',
      },
      resultRecordCount: 12,
      returnGeometry: true,
    );

    if (parcels.isEmpty) {
      parcels = await fetchParcelsByLatLongBox(
        west: point.longitude - tapBuffer,
        south: point.latitude - tapBuffer,
        east: point.longitude + tapBuffer,
        north: point.latitude + tapBuffer,
        resultRecordCount: 12,
        returnGeometry: true,
      );
    }

    return nearestParcel(point, parcels);
  }

  Future<List<ParcelProperty>> fetchVisibleParcels(LatLngBounds bounds) async {
    var parcels = await fetchParcelsFromArcGis(
      {
        'geometry':
            '${bounds.west},${bounds.south},${bounds.east},${bounds.north}',
        'geometryType': 'esriGeometryEnvelope',
      },
      resultRecordCount: visibleParcelLimit,
      returnGeometry: true,
    );

    if (parcels.isEmpty) {
      parcels = await fetchParcelsByLatLongBox(
        west: bounds.west,
        south: bounds.south,
        east: bounds.east,
        north: bounds.north,
        resultRecordCount: visibleParcelLimit,
        returnGeometry: true,
      );
    }

    return parcels
        .where(
          (parcel) =>
              parcel.centroid != null &&
              parcel.rings.isNotEmpty &&
              parcel.propertyAddress != null &&
              parcel.propertyAddress!.isNotEmpty,
        )
        .toList(growable: false);
  }

  Future<List<ParcelProperty>> fetchParcelsByLatLongBox({
    required double west,
    required double south,
    required double east,
    required double north,
    required int resultRecordCount,
    required bool returnGeometry,
    int resultOffset = 0,
  }) {
    return fetchParcelsFromArcGis(
      const {},
      resultRecordCount: resultRecordCount,
      returnGeometry: returnGeometry,
      resultOffset: resultOffset,
      where:
          "PAR_TYPE IN ('PARCEL','CONDO') AND Lat >= ${south.toStringAsFixed(8)} AND Lat <= ${north.toStringAsFixed(8)} AND Long >= ${west.toStringAsFixed(8)} AND Long <= ${east.toStringAsFixed(8)}",
    );
  }

  Future<List<ParcelProperty>> fetchParcelsFromArcGis(
    Map<String, String> geometryParameters, {
    required int resultRecordCount,
    required bool returnGeometry,
    int resultOffset = 0,
    String where = "PAR_TYPE IN ('PARCEL','CONDO')",
  }) async {
    Object? lastError;

    for (final layerUrl in tulsaParcelLayerUrls) {
      try {
        final queryParameters = {
          'f': 'json',
          'where': where,
          'outSR': '4326',
          'returnGeometry': returnGeometry ? 'true' : 'false',
          'outFields':
              'AccountNo,ACCT_NUM,ParcelNo,PropertyAddress,Owner,Name1,BusinessName,Address1,Address2,City,State,ZIPCode,PropertyType,YearBuilt,GrossSF,ImpSFTotal,SF,NetSF,BuiltAsSF,GrossAcre,TotalAcctValue,TotalLandValue,TotalImpValue,TaxableValue,SaleDate,SalePrice,DeedType,DocumentDate,ReceptionNo,Baths,Stories,Lat,Long',
          'resultRecordCount': resultRecordCount.toString(),
          'resultOffset': resultOffset.toString(),
          'orderByFields': 'AccountNo',
          ...geometryParameters,
        };

        if (geometryParameters.isNotEmpty) {
          queryParameters['inSR'] = '4326';
          queryParameters['spatialRel'] = 'esriSpatialRelIntersects';
        }

        final uri = Uri.parse(
          layerUrl,
        ).replace(queryParameters: queryParameters);
        final response = await http.get(uri);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('Parcel service returned ${response.statusCode}');
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final features = data['features'];

        if (features is! List || features.isEmpty) continue;

        return features
            .whereType<Map>()
            .map((feature) {
              return ParcelProperty.fromArcGisFeature(
                feature.cast<String, dynamic>(),
              );
            })
            .toList(growable: false);
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) {
      throw Exception('Parcel lookup failed: $lastError');
    }

    return [];
  }

  Future<void> selectParcelAt(LatLng point) async {
    if (isLoadingParcel) return;

    // Fast path: if the tap lands inside an already-loaded parcel polygon,
    // select it instantly and exactly — no network round-trip or centroid guess.
    final localParcel = parcelAtPointLocal(point);
    if (localParcel != null) {
      openParcelPreview(localParcel);
      return;
    }

    setState(() {
      isLoadingParcel = true;
      locationMessage = 'Loading property details...';
    });

    try {
      final parcel =
          await fetchParcelAtPoint(point) ?? await fetchParcelNearPoint(point);

      if (!mounted) return;

      setState(() {
        selectedParcel = parcel;
        isLoadingParcel = false;
        locationMessage = parcel == null
            ? 'No parcel found. Try zooming in or tapping closer to the house/lot.'
            : 'Property loaded: ${parcel.displayAddress}';
      });

      if (parcel == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No parcel found. Try zooming in or tapping closer to the house/lot.',
            ),
          ),
        );
        return;
      }

      showParcelPreview(parcel);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoadingParcel = false;
        locationMessage = 'Could not load property details.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load property details.')),
      );
    }
  }

  void scheduleVisibleParcelLoad() {
    visibleParcelLoadTimer?.cancel();
    visibleParcelLoadTimer = Timer(
      const Duration(milliseconds: 500),
      loadVisibleParcels,
    );
  }

  Future<void> loadVisibleParcels() async {
    if (!mounted || isLoadingVisibleParcels) return;

    final camera = mapController.camera;

    if (camera.zoom < visibleParcelZoom) {
      if (visibleParcels.isNotEmpty) {
        setState(() {
          visibleParcels = [];
        });
      }

      return;
    }

    setState(() {
      isLoadingVisibleParcels = true;
    });

    try {
      final parcels = await fetchVisibleParcels(camera.visibleBounds);

      if (!mounted) return;

      setState(() {
        visibleParcels = parcels;
        isLoadingVisibleParcels = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoadingVisibleParcels = false;
      });
    }
  }

  Lead? leadForParcel(ParcelProperty parcel) {
    final parcelAddressKey = normalizedAddressKey(parcel.propertyAddress);

    if (parcelAddressKey.isNotEmpty) {
      for (final lead in drivingLeads) {
        if (normalizedAddressKey(lead.address) == parcelAddressKey) {
          return lead;
        }
      }
    }

    final centroid = parcel.centroid;

    if (centroid == null) return null;

    final distance = Distance();

    for (final lead in drivingLeads) {
      if (lead.latitude == null || lead.longitude == null) continue;

      final leadPoint = LatLng(lead.latitude!, lead.longitude!);
      final meters = distance.as(LengthUnit.Meter, centroid, leadPoint);

      if (meters <= 20) return lead;
    }

    return null;
  }

  Color parcelMarkerColor(ParcelProperty parcel) {
    final lead = leadForParcel(parcel);

    if (lead == null) return const Color(0xFF8E8E93);

    return leadStatusColor(lead.status);
  }

  void openParcelPreview(ParcelProperty parcel) {
    setState(() {
      selectedParcel = parcel;
      locationMessage = 'Property loaded: ${parcel.displayAddress}';
    });

    showParcelPreview(parcel);
  }

  /// Opens the full lead details screen, refreshing this screen after any edit.
  void openLeadDetails(Lead lead) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LeadDetailsScreen(
          lead: lead,
          onUpdateLeadStatus: (leadId, status) async {
            await widget.onUpdateLeadStatus(leadId, status);
            if (mounted) setState(() {});
          },
          onUpdateLeadSource: (leadId, source) async {
            await widget.onUpdateLeadSource(leadId, source);
            if (mounted) setState(() {});
          },
          onUpdateLeadScoreData: (leadId, scoreData) async {
            await widget.onUpdateLeadScoreData(leadId, scoreData);
            if (mounted) setState(() {});
          },
          onUpdateLeadParcelData: (leadId, parcelData) async {
            await widget.onUpdateLeadParcelData(leadId, parcelData);
            if (mounted) setState(() {});
          },
          onUpdateLeadReminderData: (leadId, reminderData) async {
            await widget.onUpdateLeadReminderData(leadId, reminderData);
            if (mounted) setState(() {});
          },
          onUpdateLeadOfferData: (leadId, offerData) async {
            await widget.onUpdateLeadOfferData(leadId, offerData);
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  /// Returns the parcel under [point] from the already-loaded visible parcels
  /// using exact polygon containment — no network round-trip.
  ParcelProperty? parcelAtPointLocal(LatLng point) {
    final parcels = showOnlyTargetsOnMap
        ? marketProperties
              .where(marketPropertyPassesTargetFilters)
              .map((property) => property.parcel)
        : visibleParcels;

    for (final parcel in parcels) {
      if (parcel.rings.isNotEmpty && ringsContainPoint(parcel.rings, point)) {
        return parcel;
      }
    }

    return null;
  }

  Widget parcelStatusDot(ParcelProperty parcel) {
    return Tooltip(
      message: parcel.displayAddress,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: parcelMarkerColor(parcel),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget parcelHouseNumberLabel(ParcelProperty parcel, String houseNumber) {
    return Tooltip(
      message: parcel.displayAddress,
      child: Container(
        constraints: const BoxConstraints(minWidth: 38, maxWidth: 64),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xF7FFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: parcelMarkerColor(parcel), width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          houseNumber,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF202124),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  Widget parcelPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void showParcelPreview(ParcelProperty parcel) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        var isSaving = false;
        // Distress flags captured live while looking at the property.
        var vacant = false;
        var roof = false;
        var trash = false;
        var broken = false;
        var grass = false;
        final existingLead = leadForParcel(parcel);
        final marketProperty = marketPropertyForParcel(parcel);

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final smartScore = calculateSmartLeadScore(
              vacantAppearance: vacant,
              roofDamage: roof,
              trashInYard: trash,
              brokenWindows: broken,
              tallGrass: grass,
              outOfStateOwner: parcel.outOfStateOwner,
              mailingAddress: parcel.mailingAddress,
              propertyAddress: parcel.propertyAddress,
              lastSaleDate: parcel.saleDate,
              assessedValue: parcel.assessedValue,
            );

            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    20 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Property Preview',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (marketProperty != null) ...[
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Target score',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            targetScoreBadge(
                              marketProperty.targetScore,
                              onTap: () =>
                                  showTargetScoreBreakdown(marketProperty),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      parcelPreviewRow('Address', parcel.displayAddress),
                      parcelPreviewRow('Owner', parcel.ownerName ?? 'Not set'),
                      parcelPreviewRow(
                        'Mailing',
                        parcel.mailingAddress ?? 'Not set',
                      ),
                      parcelPreviewRow(
                        'Out of state',
                        parcel.outOfStateOwner ? 'Yes' : 'No',
                      ),
                      parcelPreviewRow(
                        'Type',
                        parcel.propertyType ?? 'Not set',
                      ),
                      parcelPreviewRow(
                        'Year built',
                        parcel.yearBuilt?.toString() ?? 'Not set',
                      ),
                      parcelPreviewRow(
                        'Sq ft',
                        formatDecimal(parcel.squareFeet),
                      ),
                      parcelPreviewRow('Lot', parcel.lotSizeDisplay),
                      parcelPreviewRow(
                        'Assessed',
                        formatMoney(parcel.assessedValue),
                      ),
                      parcelPreviewRow(
                        'Land value',
                        formatMoney(parcel.landValue),
                      ),
                      parcelPreviewRow(
                        'Imp value',
                        formatMoney(parcel.improvementValue),
                      ),
                      parcelPreviewRow(
                        'Baths',
                        formatDecimal(parcel.bathrooms),
                      ),
                      parcelPreviewRow(
                        'Stories',
                        formatDecimal(parcel.stories),
                      ),
                      parcelPreviewRow(
                        'Sale price',
                        formatMoney(parcel.salePrice),
                      ),
                      parcelPreviewRow(
                        'Sale date',
                        parcel.saleDate ?? 'Not set',
                      ),
                      parcelPreviewRow(
                        'Deed type',
                        parcel.deedType ?? 'Not set',
                      ),
                      parcelPreviewRow(
                        'Document date',
                        parcel.documentDate ?? 'Not set',
                      ),
                      parcelPreviewRow(
                        'Reception no',
                        parcel.receptionNo ?? 'Not set',
                      ),
                      const Divider(height: 32),
                      if (existingLead != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Already a lead (${normalizeLeadStage(existingLead.status)}).',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            leadScoreBadge(existingLead.score, fontSize: 14),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              openLeadDetails(existingLead);
                            },
                            child: const Text('Open existing lead'),
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'What did you see?',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Text('Smart score  '),
                            leadScoreBadge(smartScore, fontSize: 14),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            FilterChip(
                              label: const Text('Vacant'),
                              selected: vacant,
                              onSelected: (v) =>
                                  setSheetState(() => vacant = v),
                            ),
                            FilterChip(
                              label: const Text('Roof damage'),
                              selected: roof,
                              onSelected: (v) => setSheetState(() => roof = v),
                            ),
                            FilterChip(
                              label: const Text('Trash in yard'),
                              selected: trash,
                              onSelected: (v) => setSheetState(() => trash = v),
                            ),
                            FilterChip(
                              label: const Text('Broken windows'),
                              selected: broken,
                              onSelected: (v) =>
                                  setSheetState(() => broken = v),
                            ),
                            FilterChip(
                              label: const Text('Tall grass'),
                              selected: grass,
                              onSelected: (v) => setSheetState(() => grass = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    setSheetState(() {
                                      isSaving = true;
                                    });

                                    final scoreData = LeadScoreData(
                                      brokenWindows: broken,
                                      roofDamage: roof,
                                      tallGrass: grass,
                                      trashInYard: trash,
                                      exteriorWear: false,
                                      vacantAppearance: vacant,
                                      score: smartScore,
                                      scoreOverride: false,
                                    );

                                    try {
                                      final pendingBefore =
                                          await refreshPendingLeadsQueueCount();
                                      await widget.onAddParcelLead(
                                        parcel,
                                        scoreData,
                                        missionIdForPoint(parcel.centroid),
                                      );
                                      final pendingAfter =
                                          await refreshPendingLeadsQueueCount();

                                      await loadDrivingLeads();
                                      final ledgerMissions = [
                                        ...completedMissions,
                                      ];
                                      if (activeMission != null) {
                                        ledgerMissions.insert(
                                          0,
                                          activeMission!,
                                        );
                                      }
                                      await loadMissionLeadLedger(
                                        ledgerMissions,
                                      );

                                      if (!mounted || !sheetContext.mounted) {
                                        return;
                                      }

                                      Navigator.pop(sheetContext);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            pendingAfter > pendingBefore
                                                ? 'Lead saved locally - will sync when connected.'
                                                : 'Parcel lead added.',
                                          ),
                                        ),
                                      );
                                    } catch (_) {
                                      if (!mounted) return;

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Could not add parcel lead.',
                                          ),
                                        ),
                                      );
                                    } finally {
                                      if (sheetContext.mounted) {
                                        setSheetState(() {
                                          isSaving = false;
                                        });
                                      }
                                    }
                                  },
                            child: Text(isSaving ? 'Adding...' : 'Add Lead'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: isSaving
                              ? null
                              : () => Navigator.pop(sheetContext),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> checkLocationPermission() async {
    bool serviceEnabled;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    } catch (error) {
      if (!mounted) return false;

      final message = locationErrorMessage(error);
      setState(() {
        locationMessage = message;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return false;
    }

    if (!serviceEnabled) {
      unawaited(FieldTestLogger.log('gps_service_disabled'));
      if (!mounted) return false;

      const message = 'Location services are turned off.';
      setState(() {
        locationMessage = message;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(message)));
      return false;
    }

    LocationPermission permission;

    try {
      permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        unawaited(FieldTestLogger.log('gps_permission_request'));
        permission = await Geolocator.requestPermission();
      }
    } catch (error) {
      if (!mounted) return false;

      final message = locationErrorMessage(error);
      setState(() {
        locationMessage = message;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return false;
    }

    if (permission == LocationPermission.denied) {
      unawaited(FieldTestLogger.log('gps_permission_denied'));
      if (!mounted) return false;

      const message = 'Location permission denied.';
      setState(() {
        locationMessage = message;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(message)));
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      unawaited(FieldTestLogger.log('gps_permission_denied_forever'));
      if (!mounted) return false;

      const message = 'Location permission permanently denied.';
      setState(() {
        locationMessage = message;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(message)));
      return false;
    }

    unawaited(FieldTestLogger.log('gps_permission_ready'));
    return true;
  }

  String locationErrorMessage(Object error) {
    final details = error.toString();

    if (details.contains('NSLocationWhenInUseUsageDescription') ||
        details.contains('NSLocationAlwaysAndWhenInUseUsageDescription') ||
        details.contains('Info.plist')) {
      return 'Location permission is not configured for iPhone. Pull the latest build and reinstall the app.';
    }

    if (details.toLowerCase().contains('denied')) {
      return 'Location permission denied. Enable location access in iPhone Settings.';
    }

    if (details.toLowerCase().contains('disabled')) {
      return 'Location services are turned off.';
    }

    if (details.toLowerCase().contains('timeout')) {
      return 'Location timed out. Try again outside with a clearer GPS signal.';
    }

    return 'Could not get your location: $details';
  }

  Future<bool> findMyLocation({String reason = 'find_me'}) async {
    if (!mounted) return false;

    unawaited(FieldTestLogger.log('gps_find_start', detail: reason));
    setState(() {
      isFindingLocation = true;
      locationMessage = 'Finding your location...';
    });

    final allowed = await checkLocationPermission();

    if (!allowed) {
      if (!mounted) return false;

      setState(() {
        isFindingLocation = false;
      });
      unawaited(FieldTestLogger.log('gps_find_blocked', detail: reason));
      return false;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 15),
        ),
      );
      unawaited(
        FieldTestLogger.log(
          'gps_acquired',
          detail: 'accuracy: ${position.accuracy}m',
        ),
      );

      final newLocation = LatLng(position.latitude, position.longitude);
      final lowAccuracyMessage = isLowAccuracyPosition(position)
          ? lowAccuracyLocationMessage(position)
          : null;

      if (!mounted) return false;

      setState(() {
        myLocation = newLocation;
        lastKnownPosition = position;
        currentMapCenter = newLocation;
        followMyLocation = true;
        isFindingLocation = false;
        locationMessage =
            lowAccuracyMessage ?? 'Location found. Follow mode on.';
      });

      if (mapIsReady) {
        mapController.move(newLocation, 16);
      }

      if (lowAccuracyMessage != null) {
        unawaited(
          FieldTestLogger.log(
            'gps_low_accuracy',
            detail: '${position.accuracy}m',
          ),
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(lowAccuracyMessage)));
      } else {
        unawaited(FieldTestLogger.log('gps_follow_enabled'));
      }
      return true;
    } catch (error) {
      unawaited(FieldTestLogger.log('gps_failed', detail: error.toString()));

      if (!mounted) return false;

      final message = locationErrorMessage(error);
      setState(() {
        isFindingLocation = false;
        locationMessage = message;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return false;
    }
  }

  Future<void> startTracking({String? sessionIdOverride}) async {
    if (isTracking) return;

    final allowed = await checkLocationPermission();

    if (!allowed) return;

    final sessionId =
        sessionIdOverride ?? 'drive-${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      isTracking = true;
      followMyLocation = true;
      currentDriveSessionId = sessionId;
      locationMessage = 'Tracking started. Follow mode on.';
      routePoints.clear();
      lastProcessedTrackingPoint = null;
      lastProcessedTrackingPointAt = null;
      lastMapFollowAt = null;
    });
    unawaited(FieldTestLogger.log('gps_tracking_started', detail: sessionId));

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );

    positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) async {
            final point = LatLng(position.latitude, position.longitude);
            final now = DateTime.now();
            gpsUpdateLogCounter++;
            if (gpsUpdateLogCounter % 10 == 0) {
              unawaited(
                FieldTestLogger.log(
                  'gps_update',
                  detail: 'accuracy: ${position.accuracy}m',
                ),
              );
            }

            if (isLowAccuracyPosition(position)) {
              if (!mounted) return;

              final message = lowAccuracyLocationMessage(position);
              setState(() {
                myLocation = point;
                lastKnownPosition = position;
                locationMessage = message;
              });
              if (gpsUpdateLogCounter % 5 == 0) {
                unawaited(
                  FieldTestLogger.log(
                    'gps_low_accuracy',
                    detail: '${position.accuracy}m',
                  ),
                );
              }
              return;
            }

            final lastPoint = lastProcessedTrackingPoint;
            final lastAt = lastProcessedTrackingPointAt;
            if (lastPoint != null && lastAt != null) {
              final movedMiles = const Distance().as(
                LengthUnit.Mile,
                lastPoint,
                point,
              );
              final tooSoon =
                  now.difference(lastAt) < trackingPointMinInterval &&
                  movedMiles < trackingPointMinDistanceMiles;

              if (tooSoon || isHandlingTrackingPoint) {
                if (!mounted) return;

                setState(() {
                  myLocation = point;
                  lastKnownPosition = position;
                });
                return;
              }
            } else if (isHandlingTrackingPoint) {
              return;
            }

            isHandlingTrackingPoint = true;

            try {
              if (!mounted) return;

              setState(() {
                myLocation = point;
                lastKnownPosition = position;
                routePoints.add(point);
                locationMessage =
                    'Tracking route... Points: ${routePoints.length}';
              });

              if (followMyLocation &&
                  mapIsReady &&
                  (lastMapFollowAt == null ||
                      now.difference(lastMapFollowAt!) >
                          const Duration(seconds: 2))) {
                mapController.move(point, 17);
                lastMapFollowAt = now;
              }

              await saveDrivingPoint(point, currentDriveSessionId);
              await markNearbyStreetsCovered(point, currentDriveSessionId);
              lastProcessedTrackingPoint = point;
              lastProcessedTrackingPointAt = now;
            } finally {
              isHandlingTrackingPoint = false;
            }
          },
        );
  }

  Future<void> saveDrivingPoint(LatLng point, String? driveSessionId) async {
    try {
      await supabase.from('driving_points').insert({
        'user_id': supabase.auth.currentUser?.id,
        'account_id': widget.activeAccountId,
        'created_by': supabase.auth.currentUser?.id,
        'latitude': point.latitude,
        'longitude': point.longitude,
        'drive_session_id': driveSessionId,
      });
    } catch (_) {
      await supabase.from('driving_points').insert({
        'user_id': supabase.auth.currentUser?.id,
        'account_id': widget.activeAccountId,
        'created_by': supabase.auth.currentUser?.id,
        'latitude': point.latitude,
        'longitude': point.longitude,
      });
    }
  }

  Future<void> simulateDrive() async {
    final sessionId = 'sim-${DateTime.now().millisecondsSinceEpoch}';
    final startPoint = myLocation ?? currentMapCenter;
    final simulatedPoints = List.generate(
      8,
      (index) => LatLng(
        startPoint.latitude + (index * 0.00025),
        startPoint.longitude + (index * 0.00035),
      ),
    );

    setState(() {
      currentDriveSessionId = sessionId;
      routePoints.clear();
      myLocation = simulatedPoints.last;
      currentMapCenter = simulatedPoints.last;
      locationMessage = 'Simulating drive...';
    });

    mapController.move(simulatedPoints.last, 17);

    for (final point in simulatedPoints) {
      await saveDrivingPoint(point, sessionId);
      await markNearbyStreetsCovered(point, sessionId);
    }

    await loadSavedDrivingPoints();

    if (!mounted) return;

    setState(() {
      currentDriveSessionId = null;
      locationMessage =
          'Simulated drive saved. Points: ${simulatedPoints.length}';
    });
  }

  Future<void> stopTracking() async {
    await positionStream?.cancel();
    positionStream = null;

    final savedPointCount = routePoints.length;

    await loadSavedDrivingPoints();
    if (!mounted) return;

    setState(() {
      isTracking = false;
      followMyLocation = false;
      currentDriveSessionId = null;
      routePoints.clear();
      isHandlingTrackingPoint = false;
      lastProcessedTrackingPoint = null;
      lastProcessedTrackingPointAt = null;
      lastMapFollowAt = null;
      locationMessage = 'Tracking stopped. Points saved: $savedPointCount';
    });
    unawaited(
      FieldTestLogger.log('gps_tracking_stopped', detail: '$savedPointCount'),
    );
  }

  void openAddLeadFromLocation() {
    final missionId = missionIdForPoint(myLocation);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddLeadScreen(
          onAddLead:
              (
                address,
                condition,
                notes,
                source,
                scoreData,
                latitude,
                longitude, [
                missionId,
              ]) async {
                await widget.onAddLead(
                  address,
                  condition,
                  notes,
                  source,
                  scoreData,
                  latitude,
                  longitude,
                  missionId,
                );
                await loadDrivingLeads();
                final ledgerMissions = [...completedMissions];
                if (activeMission != null) {
                  ledgerMissions.insert(0, activeMission!);
                }
                await loadMissionLeadLedger(ledgerMissions);
              },
          latitude: myLocation?.latitude,
          longitude: myLocation?.longitude,
          missionId: missionId,
        ),
      ),
    );
  }

  bool leadPassesMapFilter(Lead lead) {
    if (!showLeadsOnMap) return false;
    if (lead.latitude == null || lead.longitude == null) return false;
    if (!selectedLeadStages.contains(normalizeLeadStage(lead.status))) {
      return false;
    }
    if (useMinLeadScore && lead.score < minLeadScore) return false;
    return true;
  }

  void openLeadFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void apply(VoidCallback change) {
              setSheetState(change);
              setState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Lead Map Filters',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Show leads on map'),
                        value: showLeadsOnMap,
                        onChanged: (value) =>
                            apply(() => showLeadsOnMap = value),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Pipeline stage',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: leadStatusOptions.map((stage) {
                          final selected = selectedLeadStages.contains(stage);
                          return FilterChip(
                            label: Text(stage),
                            selected: selected,
                            onSelected: (value) => apply(() {
                              if (value) {
                                selectedLeadStages.add(stage);
                              } else {
                                selectedLeadStages.remove(stage);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => apply(
                              () => selectedLeadStages = {...leadStatusOptions},
                            ),
                            child: const Text('Select all'),
                          ),
                          TextButton(
                            onPressed: () =>
                                apply(() => selectedLeadStages = {}),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Filter by minimum lead score'),
                        value: useMinLeadScore,
                        onChanged: (value) =>
                            apply(() => useMinLeadScore = value),
                      ),
                      Text(
                        'Minimum lead score: ${minLeadScore.round()}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: useMinLeadScore
                              ? null
                              : Theme.of(sheetContext).disabledColor,
                        ),
                      ),
                      Slider(
                        min: 0,
                        max: 100,
                        divisions: 100,
                        label: minLeadScore.round().toString(),
                        value: minLeadScore,
                        onChanged: useMinLeadScore
                            ? (value) => apply(() => minLeadScore = value)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final completedRouteSegments = drivingPointRouteSegments(
      savedDrivingPoints,
    );
    final activeRouteSegments = splitRouteSegments(routePoints);
    final totalRoutePoints = savedDrivingPoints.length + routePoints.length;
    final totalMiles =
        drivingPointMiles(savedDrivingPoints) + routeMiles(routePoints);
    final leadsFound = drivingLeads.length;
    final leadsPerMile = totalMiles == 0 ? 0 : leadsFound / totalMiles;
    final streetIds = cityStreets.map((street) => street.id).toSet();
    final visibleCoveredStreetCount = coveredStreetIds
        .where(streetIds.contains)
        .length;
    final coveredStreetCount = coveredStreetIds.length;
    final totalStreetCount = totalCityStreetCount == 0
        ? cityStreets.length
        : totalCityStreetCount;
    final remainingStreetCount = math.max(
      0,
      totalStreetCount - coveredStreetCount,
    );
    // Mileage-weighted coverage: a long arterial counts more than a cul-de-sac.
    final coverageSegments = cityStreets
        .map((street) => CoverageSegment(id: street.id, path: street.path))
        .toList();
    final estimatedCityStreetMiles = coverageSegments.fold<double>(
      0,
      (sum, segment) => sum + segment.lengthMiles,
    );
    final streetCoveragePercent = totalStreetCount == 0
        ? 0.0
        : (coveredStreetCount / totalStreetCount) * 100;
    final isStreetCoverageLoading =
        isLoadingCoverage || isLoadingStreetCoverage;
    final hasStreetReferenceData = totalStreetCount > 0;
    final coverageHeadline = isStreetCoverageLoading
        ? 'Loading saved coverage...'
        : hasStreetReferenceData
        ? '$selectedCoverageCity coverage'
        : 'No street data loaded for $selectedCoverageCity yet.';
    final coveredStreets = cityStreets
        .where((street) => coveredStreetIds.contains(street.id))
        .toList();
    final uncoveredStreets = cityStreets
        .where((street) => !coveredStreetIds.contains(street.id))
        .toList();
    final activeAreaPolygon = activeDriveArea?.polygon ?? const <LatLng>[];
    final shouldShowSavedAreaBoundaries =
        !isDrawAreaMode || showSavedAreasWhileDrawing;
    final driveAreaBoundaryAreas = shouldShowSavedAreaBoundaries
        ? (showAllDriveAreaBoundaries
              ? driveAreas
              : activeDriveArea == null
              ? const <DriveArea>[]
              : [activeDriveArea!])
        : const <DriveArea>[];
    final activeAreaStreets = activeAreaPolygon.length < 3
        ? <CityStreet>[]
        : cityStreets
              .where(
                (street) => streetFallsInsidePolygon(street, activeAreaPolygon),
              )
              .toList();
    final activeAreaCoverageSegments = activeAreaStreets
        .map((street) => CoverageSegment(id: street.id, path: street.path))
        .toList(growable: false);
    final activeAreaTotalMiles = activeAreaCoverageSegments.fold<double>(
      0,
      (sum, segment) => sum + segment.lengthMiles,
    );
    final activeAreaCoveredMiles = coveredMiles(
      activeAreaCoverageSegments,
      coveredStreetIds,
    );
    final activeAreaCoveredStreetCount = activeAreaStreets
        .where((street) => coveredStreetIds.contains(street.id))
        .length;
    final activeAreaRemainingStreetCount = math.max(
      0,
      activeAreaStreets.length - activeAreaCoveredStreetCount,
    );
    final activeAreaCoveragePercent = activeAreaStreets.isEmpty
        ? 0.0
        : (activeAreaCoveredStreetCount / activeAreaStreets.length) * 100;
    final activeAreaUncoveredStreets = activeAreaStreets
        .where((street) => !coveredStreetIds.contains(street.id))
        .toList();
    final activeAreaCoveredStreets = activeAreaStreets
        .where((street) => coveredStreetIds.contains(street.id))
        .toList();
    final activeAreaLeadsFound = activeAreaPolygon.length < 3
        ? 0
        : drivingLeads.where((lead) {
            if (lead.latitude == null || lead.longitude == null) return false;

            return pointInRing(
              LatLng(lead.latitude!, lead.longitude!),
              activeAreaPolygon,
            );
          }).length;
    final hasActiveArea = activeDriveArea != null;
    final limitMapToActiveArea = showOnlyActiveArea && hasActiveArea;
    final mapCoveredStreets = limitMapToActiveArea
        ? activeAreaCoveredStreets
        : coveredStreets;
    final mapUncoveredStreets = limitMapToActiveArea
        ? activeAreaUncoveredStreets
        : uncoveredStreets;
    final mapLeads = drivingLeads.where(leadPassesMapFilter).where((lead) {
      if (!limitMapToActiveArea || activeAreaPolygon.length < 3) return true;

      return pointInRing(
        LatLng(lead.latitude!, lead.longitude!),
        activeAreaPolygon,
      );
    }).toList();
    final filteredMarketProperties = marketProperties
        .where(marketPropertyPassesTargetFilters)
        .toList(growable: false);
    filteredMarketProperties.sort(
      (a, b) => b.targetScore.compareTo(a.targetScore),
    );
    final targetParcels = filteredMarketProperties
        .map((property) => property.parcel)
        .where((parcel) => parcel.centroid != null)
        .toList(growable: false);
    final showDriveMap = mapMode == 'drive';
    final showMissionMap = mapMode == 'mission';
    final showTargetsMap = mapMode == 'targets';
    final showCoverageMap = mapMode == 'coverage';
    final shouldDrawParcelLayer =
        showTargetsMap ||
        ((showDriveMap || showMissionMap) && currentZoom >= visibleParcelZoom);
    final mapParcels = shouldDrawParcelLayer
        ? (showTargetsMap || showOnlyTargetsOnMap
              ? targetParcels
              : visibleParcels)
        : <ParcelProperty>[];
    final streetOpportunities = cachedStreetOpportunitiesForActiveArea(
      activeAreaStreets,
      marketProperties,
    );
    final topUncoveredOpportunities = streetOpportunities
        .where((opportunity) => !opportunity.isCovered && opportunity.score > 0)
        .take(5)
        .toList(growable: false);
    final missionStreetIds = activeMission?.targetStreetIds ?? const <String>[];
    final missionOpportunities = missionStreetIds
        .map(
          (streetId) => streetOpportunities
              .where((opportunity) => opportunity.street.id == streetId)
              .firstOrNull,
        )
        .whereType<StreetOpportunity>()
        .toList(growable: false);
    final uncoveredMissionOpportunities = missionOpportunities
        .where(
          (opportunity) => !coveredStreetIds.contains(opportunity.street.id),
        )
        .toList(growable: false);
    final missionCoveredCount = missionCoveredStreetCount(
      activeMission,
      coveredStreetIds,
    );
    final missionStreetTotal = missionStreetTotalFor(activeMission);
    final missionOpportunityRemaining = uncoveredMissionOpportunities
        .fold<double>(0, (total, opportunity) => total + opportunity.score);
    final missionOpportunityAtStart = activeMission?.opportunityAtStart ?? 0;
    final missionOpportunityCaptured = safeMissionOpportunityCaptured(
      opportunityAtStart: missionOpportunityAtStart,
      opportunityRemaining: missionOpportunityRemaining,
    );
    final hasMissionOpportunityScore =
        missionOpportunityAtStart > 0 || missionOpportunityRemaining > 0;
    final nextMissionStreet = chooseNextMissionStreet(
      uncoveredMissionOpportunities,
    );
    final missionEstimatedMinutesRemaining = estimatedMinutesForMissionStreets(
      uncoveredMissionOpportunities,
    );
    final missionBudgetMinutes = activeMission?.timeBudgetMinutes;
    final missionElapsedMinutes = activeMission?.startedAt == null
        ? 0
        : DateTime.now()
              .toUtc()
              .difference(activeMission!.startedAt!.toUtc())
              .inMinutes;
    final isMissionOverTimeBudget =
        missionBudgetMinutes != null &&
        activeMission?.startedAt != null &&
        missionElapsedMinutes > missionBudgetMinutes;
    final selectedTimeBudgetMinutes =
        selectedMissionTimeBudgetMinutes ?? parsedCustomMissionMinutes();
    final previewMissionStreets = selectedTimeBudgetMinutes == null
        ? const <StreetOpportunity>[]
        : selectMissionStreetsForBudget(
            streetOpportunities,
            selectedTimeBudgetMinutes,
          );
    final previewMissionEstimatedMinutes = estimatedMinutesForMissionStreets(
      previewMissionStreets,
    );
    final previewMissionOpportunity = previewMissionStreets.fold<double>(
      0,
      (total, opportunity) => total + opportunity.score,
    );
    final missionLeads = leadsForMission(activeMission);
    final missionLeadsFound = missionLeads.length;
    final missionMiles = activeMission?.driveSessionId == null
        ? 0.0
        : drivingPointMiles([
            ...savedDrivingPoints.where(
              (point) => point.driveSessionId == activeMission!.driveSessionId,
            ),
            ...routePoints.map(
              (point) => DrivingPoint(
                point: point,
                createdAt: DateTime.now(),
                driveSessionId: activeMission!.driveSessionId,
              ),
            ),
          ]);
    final activeAreaRemainingOpportunity = remainingOpportunityForArea(
      marketProperties,
      activeAreaStreets,
      coveredStreetIds,
    );
    final rankedDriveAreas = [...driveAreas];
    final sortedCompletedMissions = [...completedMissions];
    sortedCompletedMissions.sort((a, b) {
      final aMiles = milesForMission(a);
      final bMiles = milesForMission(b);
      final aYield = aMiles == 0 ? 0.0 : leadsForMission(a).length / aMiles;
      final bYield = bMiles == 0 ? 0.0 : leadsForMission(b).length / bMiles;

      return bYield.compareTo(aYield);
    });
    if (activeDriveArea != null) {
      driveAreaRemainingOpportunity[activeDriveArea!.id] =
          activeAreaRemainingOpportunity;
    }
    rankedDriveAreas.sort(
      (a, b) => (driveAreaRemainingOpportunity[b.id] ?? 0).compareTo(
        driveAreaRemainingOpportunity[a.id] ?? 0,
      ),
    );
    final drawingBoundaryPoints = drawingAreaPoints.length > 2
        ? [...drawingAreaPoints, drawingAreaPoints.first]
        : drawingAreaPoints;
    final showHouseNumberLabels = currentZoom >= houseNumberLabelZoom;
    final heatOpportunities = (showMissionMap || showTargetsMap)
        ? streetOpportunities
              .where((opportunity) => opportunity.score > 0)
              .toList(growable: false)
        : <StreetOpportunity>[];
    final shouldDrawLeads = showDriveMap || showMissionMap || showTargetsMap;
    final routeToStartPoints =
        showRouteToStartLine &&
            activeMission?.missionStartPoint != null &&
            myLocation != null
        ? [myLocation!, activeMission!.missionStartPoint!]
        : const <LatLng>[];

    final missionPercent = safePercent(missionCoveredCount, missionStreetTotal);
    final nextStreetName = nextMissionStreet?.street.streetName.isEmpty ?? true
        ? 'Unnamed street'
        : nextMissionStreet!.street.streetName;
    final showLegacyDriveControls = isDrawAreaMode && DateTime.now().year < 0;
    final today = dateOnly(DateTime.now());
    final todayScheduledMission = activeMission == null
        ? scheduledMissions
              .where(
                (mission) => isSameCalendarDate(mission.scheduledDate, today),
              )
              .firstOrNull
        : null;
    final todayScheduledOpportunities = todayScheduledMission == null
        ? const <StreetOpportunity>[]
        : todayScheduledMission.targetStreetIds
              .map(
                (streetId) => streetOpportunities
                    .where((opportunity) => opportunity.street.id == streetId)
                    .firstOrNull,
              )
              .whereType<StreetOpportunity>()
              .toList(growable: false);
    final todayScheduledEstimatedMinutes = todayScheduledOpportunities.isEmpty
        ? todayScheduledMission?.estimatedMinutes ?? 0
        : estimatedMinutesForMissionStreets(todayScheduledOpportunities);
    final hasNoDriveAreas = !isLoadingDriveAreas && driveAreas.isEmpty;
    final showFirstMissionTip =
        !isLoadingDriveAreas &&
        driveAreas.isNotEmpty &&
        !hasCompletedMissionEver &&
        !firstMissionTipDismissed;
    final planPanelHeight = todayScheduledMission == null
        ? (showFirstMissionTip ? 172.0 : 92.0)
        : (showFirstMissionTip ? 262.0 : 182.0);
    final findMeButtonBottom = activeMission == null
        ? (hasNoDriveAreas ? 24.0 : planPanelHeight + 16)
        : 86.0;
    final locationStatusTop = driveAreas.length > 1 && !isDrawAreaMode
        ? 112.0
        : 64.0;
    final activeCityLabel = MarketService.getActiveCity().isEmpty
        ? selectedCoverageCity
        : MarketService.getActiveCity();

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: SizedBox(
              key: mapWorkspaceKey,
              width: double.infinity,
              height: MediaQuery.of(context).size.height,
              child: FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: currentMapCenter,
                  initialZoom: 13,
                  onMapReady: () {
                    mapIsReady = true;
                    currentZoom = mapController.camera.zoom;
                    if (myLocation != null) {
                      mapController.move(
                        myLocation!,
                        math.max(currentZoom, 16),
                      );
                    }
                    loadVisibleParcels();
                    loadVisibleCityStreets();
                  },
                  onPositionChanged: handleMapPositionChanged,
                  onTap: (_, point) => handleMapTap(point),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.market_coverage',
                  ),
                  if (completedRouteSegments.isNotEmpty)
                    PolylineLayer(
                      polylines: completedRouteSegments
                          .map(
                            (points) => Polyline(
                              points: points,
                              strokeWidth: 2,
                              color: const Color(0x665F6368),
                            ),
                          )
                          .toList(),
                    ),
                  if (showCoverageMap && mapUncoveredStreets.isNotEmpty)
                    PolylineLayer(
                      polylines: mapUncoveredStreets
                          .map(
                            (street) => Polyline(
                              points: street.path,
                              strokeWidth: 2,
                              color: const Color(0x66E53935),
                            ),
                          )
                          .toList(),
                    ),
                  if (showCoverageMap && mapCoveredStreets.isNotEmpty)
                    PolylineLayer(
                      polylines: mapCoveredStreets
                          .map(
                            (street) => Polyline(
                              points: street.path,
                              strokeWidth: 4,
                              color: const Color(0xCC2E7D32),
                            ),
                          )
                          .toList(),
                    ),
                  if (heatOpportunities.isNotEmpty)
                    PolylineLayer(
                      polylines: heatOpportunities
                          .map(
                            (opportunity) => Polyline(
                              points: opportunity.street.path,
                              strokeWidth: opportunity.score > 0 ? 6 : 3,
                              color: streetOpportunityColor(opportunity),
                            ),
                          )
                          .toList(),
                    ),
                  if (showMissionMap && missionOpportunities.isNotEmpty)
                    PolylineLayer(
                      polylines: missionOpportunities
                          .map(
                            (opportunity) => Polyline(
                              points: opportunity.street.path,
                              strokeWidth:
                                  coveredStreetIds.contains(
                                    opportunity.street.id,
                                  )
                                  ? 3.5
                                  : 2.5,
                              color:
                                  coveredStreetIds.contains(
                                    opportunity.street.id,
                                  )
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFE53935),
                            ),
                          )
                          .toList(),
                    ),
                  if (showMissionMap && nextMissionStreet != null)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: nextMissionStreet.street.path,
                          strokeWidth: 4,
                          color: const Color(0xFF2196F3),
                        ),
                      ],
                    ),
                  if (showDriveMap &&
                      !limitMapToActiveArea &&
                      activeAreaUncoveredStreets.isNotEmpty)
                    PolylineLayer(
                      polylines: activeAreaUncoveredStreets
                          .map(
                            (street) => Polyline(
                              points: street.path,
                              strokeWidth: 5,
                              color: const Color(0xFFFF9800),
                            ),
                          )
                          .toList(),
                    ),
                  if (driveAreaBoundaryAreas.any(
                    (area) => area.polygon.length >= 3,
                  ))
                    PolygonLayer(
                      polygons: driveAreaBoundaryAreas
                          .where((area) => area.polygon.length >= 3)
                          .map((area) {
                            final isActive = area.id == activeDriveArea?.id;

                            return Polygon(
                              points: area.polygon,
                              color: isActive
                                  ? const Color(0x1A1976D2)
                                  : const Color(0x0F111827),
                              borderColor: isActive
                                  ? const Color(0xFF0D47A1)
                                  : const Color(0xFF6B7280),
                              borderStrokeWidth: isActive ? 4 : 2,
                            );
                          })
                          .toList(),
                    ),
                  if (drawingBoundaryPoints.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: drawingBoundaryPoints,
                          strokeWidth: 4,
                          color: const Color(0xFF7B1FA2),
                        ),
                      ],
                    ),
                  if (drawingAreaPoints.length >= 3)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: drawingAreaPoints,
                          color: const Color(0x247B1FA2),
                          borderColor: const Color(0xFF7B1FA2),
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),
                  if (mapParcels.any((parcel) => parcel.rings.isNotEmpty))
                    PolygonLayer(
                      polygons: mapParcels
                          .where((parcel) => parcel.rings.isNotEmpty)
                          .expand(
                            (parcel) => parcel.rings.map(
                              (ring) => Polygon(
                                points: ring,
                                color: Colors.transparent,
                                borderColor: const Color(0xCC4F5257),
                                borderStrokeWidth: 1.6,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  if (selectedParcel != null &&
                      selectedParcel!.rings.isNotEmpty)
                    PolygonLayer(
                      polygons: selectedParcel!.rings
                          .map(
                            (ring) => Polygon(
                              points: ring,
                              color: const Color(0x262196F3),
                              borderColor: const Color(0xFF1565C0),
                              borderStrokeWidth: 4,
                            ),
                          )
                          .toList(),
                    ),
                  if (isTracking && activeRouteSegments.isNotEmpty)
                    PolylineLayer(
                      polylines: activeRouteSegments
                          .map(
                            (points) => Polyline(
                              points: points,
                              strokeWidth: 5,
                              color: Colors.blue,
                            ),
                          )
                          .toList(),
                    ),
                  if (routeToStartPoints.length == 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: routeToStartPoints,
                          strokeWidth: 4,
                          color: const Color(0xFF2563EB),
                        ),
                      ],
                    ),
                  if (mapParcels.isNotEmpty)
                    MarkerLayer(
                      markers: mapParcels
                          .where((parcel) => parcel.centroid != null)
                          .map((parcel) {
                            final houseNumber = houseNumberFromAddress(
                              parcel.propertyAddress,
                            );
                            final showLabel =
                                showHouseNumberLabels && houseNumber != null;

                            return Marker(
                              point: parcel.centroid!,
                              width: showLabel ? 66 : 28,
                              height: 32,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => openParcelPreview(parcel),
                                child: Center(
                                  child: showLabel
                                      ? parcelHouseNumberLabel(
                                          parcel,
                                          houseNumber,
                                        )
                                      : parcelStatusDot(parcel),
                                ),
                              ),
                            );
                          })
                          .toList(),
                    ),
                  if (myLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: myLocation!,
                          width: 50,
                          height: 50,
                          child: buildUserLocationMarker(),
                        ),
                      ],
                    ),
                  if (drawingAreaPoints.isNotEmpty)
                    MarkerLayer(
                      markers: drawingAreaPoints
                          .asMap()
                          .entries
                          .map(
                            (entry) => Marker(
                              point: entry.value,
                              width: 30,
                              height: 30,
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7B1FA2),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: Text(
                                  '${entry.key + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  if (shouldDrawLeads)
                    MarkerLayer(
                      markers: mapLeads
                          .map(
                            (lead) => Marker(
                              point: LatLng(lead.latitude!, lead.longitude!),
                              width: 28,
                              height: 28,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => openLeadDetails(lead),
                                child: Center(
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: leadScoreColor(lead.score),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: leadStatusColor(lead.status),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
          if (showLegacyDriveControls)
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          coverageHeadline,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(locationMessage),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            SizedBox(
                              width: 210,
                              height: 44,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: followMyLocation
                                      ? const Color(0xFF2563EB)
                                      : null,
                                  foregroundColor: followMyLocation
                                      ? Colors.white
                                      : null,
                                ),
                                icon: isFindingLocation
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        followMyLocation
                                            ? Icons.gps_fixed
                                            : Icons.my_location,
                                      ),
                                onPressed: isFindingLocation
                                    ? null
                                    : () => unawaited(findMyLocation()),
                                label: Text(
                                  isFindingLocation
                                      ? 'Finding...'
                                      : followMyLocation
                                      ? 'Following'
                                      : 'Find Me',
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 210,
                              height: 44,
                              child: ElevatedButton.icon(
                                icon: Icon(
                                  isTracking ? Icons.stop : Icons.play_arrow,
                                ),
                                onPressed: isTracking
                                    ? stopTracking
                                    : startTracking,
                                label: Text(
                                  isTracking
                                      ? 'Stop Tracking'
                                      : 'Start Tracking',
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 210,
                              height: 44,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.route),
                                onPressed: isTracking ? null : simulateDrive,
                                label: const Text('Simulate Drive'),
                              ),
                            ),
                            SizedBox(
                              width: 210,
                              height: 44,
                              child: OutlinedButton.icon(
                                icon: Icon(
                                  isDrawAreaMode ? Icons.edit_off : Icons.edit,
                                ),
                                label: Text(
                                  isDrawAreaMode
                                      ? 'Exit Draw Area'
                                      : 'Draw Area',
                                ),
                                onPressed: () {
                                  setState(() {
                                    isDrawAreaMode = !isDrawAreaMode;
                                    selectedParcel = null;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        if (isDrawAreaMode) ...[
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Boundary points: ${drawingAreaPoints.length}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Show saved areas'),
                                    subtitle: const Text(
                                      'Turn this on if you want old boundaries visible while drawing.',
                                    ),
                                    value: showSavedAreasWhileDrawing,
                                    onChanged: (value) {
                                      setState(() {
                                        showSavedAreasWhileDrawing = value;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: drawingAreaPoints.isEmpty
                                              ? null
                                              : undoLastDrawingPoint,
                                          child: const Text('Undo last point'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: drawingAreaPoints.isEmpty
                                              ? null
                                              : clearDrawingArea,
                                          child: const Text('Clear'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed:
                                          drawingAreaPoints.length < 3 ||
                                              isSavingDriveArea
                                          ? null
                                          : saveDrawingArea,
                                      child: Text(
                                        isSavingDriveArea
                                            ? 'Saving...'
                                            : 'Save area',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF2563EB,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    mapModeIcon(mapMode),
                                    color: const Color(0xFF2563EB),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Smart map: ${mapModeLabel(mapMode)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        mapModeDescription(mapMode),
                                        style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'Change map view',
                                  onSelected: (mode) {
                                    focusMapWorkspace(
                                      mode: mode,
                                      point: currentMapCenter,
                                      minZoom: currentZoom,
                                      message:
                                          'Map view changed to ${mapModeLabel(mode)}.',
                                    );
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'mission',
                                      child: ListTile(
                                        leading: Icon(Icons.flag),
                                        title: Text('Mission Drive'),
                                        subtitle: Text('Next street and heat'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'targets',
                                      child: ListTile(
                                        leading: Icon(Icons.adjust),
                                        title: Text('Targets'),
                                        subtitle: Text('Scored parcels'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'coverage',
                                      child: ListTile(
                                        leading: Icon(Icons.timeline),
                                        title: Text('Coverage'),
                                        subtitle: Text('Covered vs remaining'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'drive',
                                      child: ListTile(
                                        leading: Icon(Icons.directions_car),
                                        title: Text('Drive'),
                                        subtitle: Text('Light parcel tapping'),
                                      ),
                                    ),
                                  ],
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: const Color(0xFFD1D5DB),
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('Map View'),
                                        SizedBox(width: 6),
                                        Icon(Icons.expand_more),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: MediaQuery.of(context).size.height,
                          child: FlutterMap(
                            mapController: mapController,
                            options: MapOptions(
                              initialCenter: currentMapCenter,
                              initialZoom: 13,
                              onMapReady: () {
                                mapIsReady = true;
                                currentZoom = mapController.camera.zoom;
                                if (myLocation != null) {
                                  mapController.move(
                                    myLocation!,
                                    math.max(currentZoom, 16),
                                  );
                                }
                                loadVisibleParcels();
                                loadVisibleCityStreets();
                              },
                              onPositionChanged: handleMapPositionChanged,
                              onTap: (_, point) => handleMapTap(point),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName:
                                    'com.example.market_coverage',
                              ),
                              if (completedRouteSegments.isNotEmpty)
                                PolylineLayer(
                                  polylines: completedRouteSegments
                                      .map(
                                        (points) => Polyline(
                                          points: points,
                                          strokeWidth: 2,
                                          color: const Color(0x665F6368),
                                        ),
                                      )
                                      .toList(),
                                ),
                              if (showCoverageMap &&
                                  mapUncoveredStreets.isNotEmpty)
                                PolylineLayer(
                                  polylines: mapUncoveredStreets
                                      .map(
                                        (street) => Polyline(
                                          points: street.path,
                                          strokeWidth: 2,
                                          color: const Color(0x66E53935),
                                        ),
                                      )
                                      .toList(),
                                ),
                              if (showCoverageMap &&
                                  mapCoveredStreets.isNotEmpty)
                                PolylineLayer(
                                  polylines: mapCoveredStreets
                                      .map(
                                        (street) => Polyline(
                                          points: street.path,
                                          strokeWidth: 4,
                                          color: const Color(0xCC2E7D32),
                                        ),
                                      )
                                      .toList(),
                                ),
                              if (heatOpportunities.isNotEmpty)
                                PolylineLayer(
                                  polylines: heatOpportunities
                                      .map(
                                        (opportunity) => Polyline(
                                          points: opportunity.street.path,
                                          strokeWidth: opportunity.score > 0
                                              ? 6
                                              : 3,
                                          color: streetOpportunityColor(
                                            opportunity,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              if (showMissionMap &&
                                  missionOpportunities.isNotEmpty)
                                PolylineLayer(
                                  polylines: missionOpportunities
                                      .map(
                                        (opportunity) => Polyline(
                                          points: opportunity.street.path,
                                          strokeWidth:
                                              coveredStreetIds.contains(
                                                opportunity.street.id,
                                              )
                                              ? 3.5
                                              : 2.5,
                                          color:
                                              coveredStreetIds.contains(
                                                opportunity.street.id,
                                              )
                                              ? const Color(0xFF2E7D32)
                                              : const Color(0xFFE53935),
                                        ),
                                      )
                                      .toList(),
                                ),
                              if (showMissionMap && nextMissionStreet != null)
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: nextMissionStreet.street.path,
                                      strokeWidth: 4,
                                      color: const Color(0xFF2196F3),
                                    ),
                                  ],
                                ),
                              if (showDriveMap &&
                                  !limitMapToActiveArea &&
                                  activeAreaUncoveredStreets.isNotEmpty)
                                PolylineLayer(
                                  polylines: activeAreaUncoveredStreets
                                      .map(
                                        (street) => Polyline(
                                          points: street.path,
                                          strokeWidth: 5,
                                          color: const Color(0xFFFF9800),
                                        ),
                                      )
                                      .toList(),
                                ),
                              if (driveAreaBoundaryAreas.any(
                                (area) => area.polygon.length >= 3,
                              ))
                                PolygonLayer(
                                  polygons: driveAreaBoundaryAreas
                                      .where((area) => area.polygon.length >= 3)
                                      .map((area) {
                                        final isActive =
                                            area.id == activeDriveArea?.id;

                                        return Polygon(
                                          points: area.polygon,
                                          color: isActive
                                              ? const Color(0x1A1976D2)
                                              : const Color(0x0F111827),
                                          borderColor: isActive
                                              ? const Color(0xFF0D47A1)
                                              : const Color(0xFF6B7280),
                                          borderStrokeWidth: isActive ? 4 : 2,
                                        );
                                      })
                                      .toList(),
                                ),
                              if (drawingBoundaryPoints.length > 1)
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: drawingBoundaryPoints,
                                      strokeWidth: 4,
                                      color: const Color(0xFF7B1FA2),
                                    ),
                                  ],
                                ),
                              if (drawingAreaPoints.length >= 3)
                                PolygonLayer(
                                  polygons: [
                                    Polygon(
                                      points: drawingAreaPoints,
                                      color: const Color(0x247B1FA2),
                                      borderColor: const Color(0xFF7B1FA2),
                                      borderStrokeWidth: 2,
                                    ),
                                  ],
                                ),
                              if (mapParcels.any(
                                (parcel) => parcel.rings.isNotEmpty,
                              ))
                                PolygonLayer(
                                  polygons: mapParcels
                                      .where(
                                        (parcel) => parcel.rings.isNotEmpty,
                                      )
                                      .expand(
                                        (parcel) => parcel.rings.map(
                                          (ring) => Polygon(
                                            points: ring,
                                            color: Colors.transparent,
                                            borderColor: const Color(
                                              0xCC4F5257,
                                            ),
                                            borderStrokeWidth: 1.6,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              if (selectedParcel != null &&
                                  selectedParcel!.rings.isNotEmpty)
                                PolygonLayer(
                                  polygons: selectedParcel!.rings
                                      .map(
                                        (ring) => Polygon(
                                          points: ring,
                                          color: const Color(0x262196F3),
                                          borderColor: const Color(0xFF1565C0),
                                          borderStrokeWidth: 4,
                                        ),
                                      )
                                      .toList(),
                                ),
                              if (isTracking && activeRouteSegments.isNotEmpty)
                                PolylineLayer(
                                  polylines: activeRouteSegments
                                      .map(
                                        (points) => Polyline(
                                          points: points,
                                          strokeWidth: 5,
                                          color: Colors.blue,
                                        ),
                                      )
                                      .toList(),
                                ),
                              if (mapParcels.isNotEmpty)
                                MarkerLayer(
                                  markers: mapParcels
                                      .where(
                                        (parcel) => parcel.centroid != null,
                                      )
                                      .map((parcel) {
                                        final houseNumber =
                                            houseNumberFromAddress(
                                              parcel.propertyAddress,
                                            );
                                        final showLabel =
                                            showHouseNumberLabels &&
                                            houseNumber != null;

                                        return Marker(
                                          point: parcel.centroid!,
                                          width: showLabel ? 66 : 28,
                                          height: 32,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () =>
                                                openParcelPreview(parcel),
                                            child: Center(
                                              child: showLabel
                                                  ? parcelHouseNumberLabel(
                                                      parcel,
                                                      houseNumber,
                                                    )
                                                  : parcelStatusDot(parcel),
                                            ),
                                          ),
                                        );
                                      })
                                      .toList(),
                                ),
                              if (myLocation != null)
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: myLocation!,
                                      width: 50,
                                      height: 50,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: const BoxDecoration(
                                              color: Color(0x332196F3),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          Container(
                                            width: 18,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2196F3),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 3,
                                              ),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Color(0x33000000),
                                                  blurRadius: 4,
                                                  offset: Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              if (drawingAreaPoints.isNotEmpty)
                                MarkerLayer(
                                  markers: drawingAreaPoints
                                      .asMap()
                                      .entries
                                      .map(
                                        (entry) => Marker(
                                          point: entry.value,
                                          width: 30,
                                          height: 30,
                                          child: Container(
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF7B1FA2),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                            ),
                                            child: Text(
                                              '${entry.key + 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              if (shouldDrawLeads)
                                MarkerLayer(
                                  markers: mapLeads
                                      .map(
                                        (lead) => Marker(
                                          point: LatLng(
                                            lead.latitude!,
                                            lead.longitude!,
                                          ),
                                          width: 28,
                                          height: 28,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => openLeadDetails(lead),
                                            child: Center(
                                              child: Container(
                                                width: 18,
                                                height: 18,
                                                decoration: BoxDecoration(
                                                  color: leadScoreColor(
                                                    lead.score,
                                                  ),
                                                  shape: BoxShape.circle,
                                                ),
                                                alignment: Alignment.center,
                                                child: Container(
                                                  width: 10,
                                                  height: 10,
                                                  decoration: BoxDecoration(
                                                    color: leadStatusColor(
                                                      lead.status,
                                                    ),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Active Work Area',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Pick the area this map, mission, and coverage should work from.',
                                  style: TextStyle(color: Color(0xFF6B7280)),
                                ),
                                const SizedBox(height: 12),
                                if (isLoadingDriveAreas)
                                  const Text('Loading saved drive areas...')
                                else if (driveAreas.isEmpty)
                                  const Text('No saved drive areas yet.')
                                else ...[
                                  DropdownButtonFormField<String>(
                                    initialValue: activeDriveArea?.id,
                                    decoration: const InputDecoration(
                                      labelText: 'Active area',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: [
                                      const DropdownMenuItem<String>(
                                        value: '',
                                        child: Text('No active area'),
                                      ),
                                      ...rankedDriveAreas.map(
                                        (area) => DropdownMenuItem<String>(
                                          value: area.id,
                                          child: Text(
                                            '${area.isComplete ? '${area.name} (complete)' : area.name} '
                                            '(${(driveAreaRemainingOpportunity[area.id] ?? 0).toStringAsFixed(0)} opp)',
                                          ),
                                        ),
                                      ),
                                    ],
                                    onChanged: (areaId) {
                                      if (areaId == null) return;

                                      final area = areaId.isEmpty
                                          ? null
                                          : driveAreas
                                                .where(
                                                  (item) => item.id == areaId,
                                                )
                                                .firstOrNull;
                                      setActiveDriveArea(area);
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  if (activeDriveArea == null)
                                    const Text('Pick an area to resume it.')
                                  else ...[
                                    Text(
                                      activeDriveArea!.name,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text('City: ${activeDriveArea!.city}'),
                                    const SizedBox(height: 8),
                                    _CoverageStatBlock(
                                      streetsDriven:
                                          activeAreaCoveredStreetCount,
                                      totalStreets: activeAreaStreets.length,
                                      percent: activeAreaCoveragePercent,
                                      milesCovered: activeAreaCoveredMiles,
                                      totalMiles: activeAreaTotalMiles,
                                      remainingStreets:
                                          activeAreaRemainingStreetCount,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Leads found inside area: $activeAreaLeadsFound',
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Remaining opportunity: ${activeAreaRemainingOpportunity.toStringAsFixed(0)}',
                                    ),
                                    const SizedBox(height: 12),
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Show only active area',
                                      ),
                                      value: showOnlyActiveArea,
                                      onChanged: (value) {
                                        setState(() {
                                          showOnlyActiveArea = value;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 48,
                                      child: ElevatedButton.icon(
                                        icon: Icon(
                                          isTracking
                                              ? Icons.navigation
                                              : Icons.play_arrow,
                                        ),
                                        label: Text(
                                          isTracking
                                              ? 'Area Drive Running'
                                              : 'Start Area Drive',
                                        ),
                                        onPressed: startAreaDrive,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 48,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.near_me),
                                        label: const Text(
                                          'Next uncovered street',
                                        ),
                                        onPressed:
                                            activeAreaUncoveredStreets.isEmpty
                                            ? null
                                            : () => focusNextUncoveredStreet(
                                                activeAreaUncoveredStreets,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 48,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.map),
                                        label: Text(
                                          isBuildingMarketMap
                                              ? 'Analyzing area...'
                                              : motivatedSellersButtonLabel,
                                        ),
                                        onPressed: isBuildingMarketMap
                                            ? null
                                            : buildMarketMap,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const _MotivatedSellersDescription(),
                                    if (marketMapMessage.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(marketMapMessage),
                                    ],
                                    if (topUncoveredOpportunities
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Best uncovered streets first',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ...topUncoveredOpportunities.map(
                                        (opportunity) => ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(
                                            opportunity
                                                    .street
                                                    .streetName
                                                    .isEmpty
                                                ? 'Unnamed street'
                                                : opportunity.street.streetName,
                                          ),
                                          subtitle: Text(
                                            'Opportunity ${opportunity.score.toStringAsFixed(0)}',
                                          ),
                                          trailing: IconButton(
                                            icon: const Icon(
                                              Icons.center_focus_strong,
                                            ),
                                            tooltip: 'Pan map here',
                                            onPressed: () => focusStreetWorkspace(
                                              'mission',
                                              opportunity.street,
                                              message:
                                                  opportunity
                                                      .street
                                                      .streetName
                                                      .isEmpty
                                                  ? 'Mission map focused on this street.'
                                                  : 'Mission map focused on ${opportunity.street.streetName}.',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 16),
                                    Card(
                                      color: const Color(0xFFF7F9FC),
                                      child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Opportunity Mission',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            if (isLoadingMissions)
                                              const Text('Loading mission...')
                                            else if (activeMission == null) ...[
                                              Text(
                                                'Ready to create a ${math.min(missionStreetCount, topUncoveredOpportunities.length)} street mission.',
                                              ),
                                              const SizedBox(height: 10),
                                              Card(
                                                color: Colors.white,
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    14,
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Text(
                                                        'How much time do you have?',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      Wrap(
                                                        spacing: 8,
                                                        runSpacing: 8,
                                                        children: [
                                                          ChoiceChip(
                                                            label: const Text(
                                                              '30 min',
                                                            ),
                                                            selected:
                                                                selectedMissionTimeBudgetMinutes ==
                                                                30,
                                                            onSelected: (_) {
                                                              setState(() {
                                                                selectedMissionTimeBudgetMinutes =
                                                                    30;
                                                              });
                                                            },
                                                          ),
                                                          ChoiceChip(
                                                            label: const Text(
                                                              '1 hour',
                                                            ),
                                                            selected:
                                                                selectedMissionTimeBudgetMinutes ==
                                                                60,
                                                            onSelected: (_) {
                                                              setState(() {
                                                                selectedMissionTimeBudgetMinutes =
                                                                    60;
                                                              });
                                                            },
                                                          ),
                                                          ChoiceChip(
                                                            label: const Text(
                                                              '2 hours',
                                                            ),
                                                            selected:
                                                                selectedMissionTimeBudgetMinutes ==
                                                                120,
                                                            onSelected: (_) {
                                                              setState(() {
                                                                selectedMissionTimeBudgetMinutes =
                                                                    120;
                                                              });
                                                            },
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: TextField(
                                                              controller:
                                                                  customMissionTimeController,
                                                              keyboardType:
                                                                  TextInputType
                                                                      .number,
                                                              decoration:
                                                                  const InputDecoration(
                                                                    labelText:
                                                                        'Custom time',
                                                                  ),
                                                              onChanged: (_) {
                                                                setState(() {
                                                                  selectedMissionTimeBudgetMinutes =
                                                                      null;
                                                                });
                                                              },
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          SegmentedButton<bool>(
                                                            segments: const [
                                                              ButtonSegment(
                                                                value: false,
                                                                label: Text(
                                                                  'min',
                                                                ),
                                                              ),
                                                              ButtonSegment(
                                                                value: true,
                                                                label: Text(
                                                                  'hr',
                                                                ),
                                                              ),
                                                            ],
                                                            selected: {
                                                              customMissionTimeInHours,
                                                            },
                                                            onSelectionChanged:
                                                                (selection) {
                                                                  setState(() {
                                                                    customMissionTimeInHours =
                                                                        selection
                                                                            .first;
                                                                    selectedMissionTimeBudgetMinutes =
                                                                        null;
                                                                  });
                                                                },
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Container(
                                                        width: double.infinity,
                                                        padding:
                                                            const EdgeInsets.all(
                                                              12,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                            0xFFF3F4F6,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Expanded(
                                                              child: Text(
                                                                previewMissionStreets
                                                                        .isEmpty
                                                                    ? 'No time-budgeted streets available yet.'
                                                                    : '${previewMissionStreets.length} streets · est. $previewMissionEstimatedMinutes min · ${previewMissionOpportunity.toStringAsFixed(0)} opp pts',
                                                                style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                              ),
                                                            ),
                                                            TextButton(
                                                              onPressed: () {
                                                                ScaffoldMessenger.of(
                                                                  context,
                                                                ).showSnackBar(
                                                                  const SnackBar(
                                                                    content: Text(
                                                                      'Adjust coming soon',
                                                                    ),
                                                                  ),
                                                                );
                                                              },
                                                              child: const Text(
                                                                'Adjust',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              SizedBox(
                                                width: double.infinity,
                                                height: 46,
                                                child: ElevatedButton.icon(
                                                  icon: const Icon(Icons.flag),
                                                  label: Text(
                                                    isSavingMission
                                                        ? 'Starting...'
                                                        : 'Start Mission',
                                                  ),
                                                  onPressed:
                                                      isSavingMission ||
                                                          previewMissionStreets
                                                              .isEmpty ||
                                                          selectedTimeBudgetMinutes ==
                                                              null
                                                      ? null
                                                      : () => generateMission(
                                                          streetOpportunities,
                                                          timeBudgetMinutes:
                                                              selectedTimeBudgetMinutes,
                                                        ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              TextButton(
                                                onPressed:
                                                    isSavingMission ||
                                                        topUncoveredOpportunities
                                                            .isEmpty
                                                    ? null
                                                    : () => generateMission(
                                                        streetOpportunities,
                                                      ),
                                                child: const Text(
                                                  'Start default 12-street mission',
                                                ),
                                              ),
                                            ] else ...[
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      activeMission!.status ==
                                                              'paused'
                                                          ? 'Mission paused'
                                                          : 'Mission running',
                                                      style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    '$missionCoveredCount / $missionStreetTotal',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              LinearProgressIndicator(
                                                value:
                                                    (safePercent(
                                                              missionCoveredCount,
                                                              missionStreetTotal,
                                                            ) /
                                                            100)
                                                        .clamp(0, 1),
                                              ),
                                              const SizedBox(height: 12),
                                              Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.all(
                                                  14,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFEEF2FF,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    const Text(
                                                      'Next street',
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFF4F46E5,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      nextMissionStreet == null
                                                          ? 'Mission streets complete'
                                                          : nextMissionStreet
                                                                .street
                                                                .streetName
                                                                .isEmpty
                                                          ? 'Unnamed street'
                                                          : nextMissionStreet
                                                                .street
                                                                .streetName,
                                                      style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      hasMissionOpportunityScore
                                                          ? 'Remaining opportunity: ${missionOpportunityRemaining.toStringAsFixed(0)} pts'
                                                          : 'No opportunity score for this mission yet.',
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF4B5563,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  Chip(
                                                    avatar: const Icon(
                                                      Icons.person_pin_circle,
                                                      size: 18,
                                                    ),
                                                    label: Text(
                                                      '$missionLeadsFound leads',
                                                    ),
                                                  ),
                                                  Chip(
                                                    avatar: const Icon(
                                                      Icons.route,
                                                      size: 18,
                                                    ),
                                                    label: Text(
                                                      '${missionMiles.toStringAsFixed(2)} mi',
                                                    ),
                                                  ),
                                                  if (hasMissionOpportunityScore)
                                                    Chip(
                                                      avatar: const Icon(
                                                        Icons.bolt,
                                                        size: 18,
                                                      ),
                                                      label: Text(
                                                        '${missionOpportunityCaptured.toStringAsFixed(0)} pts captured',
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              SizedBox(
                                                width: double.infinity,
                                                child: FilledButton.icon(
                                                  icon: const Icon(
                                                    Icons.navigation,
                                                  ),
                                                  label: Text(
                                                    isTracking
                                                        ? 'Tracking mission'
                                                        : 'Drive next street',
                                                  ),
                                                  onPressed:
                                                      nextMissionStreet == null
                                                      ? null
                                                      : () async {
                                                          focusStreetWorkspace(
                                                            'mission',
                                                            nextMissionStreet
                                                                .street,
                                                            message:
                                                                'Mission map focused on your next street.',
                                                          );

                                                          if (!isTracking) {
                                                            await startMissionDriving();
                                                          }
                                                        },
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              SwitchListTile(
                                                contentPadding: EdgeInsets.zero,
                                                dense: true,
                                                title: const Text(
                                                  'Show saved areas',
                                                ),
                                                value:
                                                    showSavedAreasWhileDrawing,
                                                onChanged: (value) {
                                                  setState(() {
                                                    showSavedAreasWhileDrawing =
                                                        value;
                                                  });
                                                },
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: OutlinedButton.icon(
                                                      icon: const Icon(
                                                        Icons.pause,
                                                      ),
                                                      onPressed: pauseMission,
                                                      label: const Text(
                                                        'Pause',
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: OutlinedButton.icon(
                                                      icon: const Icon(
                                                        Icons.check_circle,
                                                      ),
                                                      onPressed: () => completeMission(
                                                        streetsCovered:
                                                            missionCoveredCount,
                                                        opportunityCaptured:
                                                            missionOpportunityCaptured,
                                                        leadsFound:
                                                            missionLeadsFound,
                                                        milesDriven:
                                                            missionMiles,
                                                      ),
                                                      label: const Text(
                                                        'Finish',
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (missionOpportunities
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 12),
                                                ExpansionTile(
                                                  tilePadding: EdgeInsets.zero,
                                                  childrenPadding:
                                                      EdgeInsets.zero,
                                                  title: const Text(
                                                    'Mission streets',
                                                  ),
                                                  subtitle: Text(
                                                    '$missionCoveredCount of $missionStreetTotal covered',
                                                  ),
                                                  children: missionOpportunities.map((
                                                    opportunity,
                                                  ) {
                                                    final isCovered =
                                                        coveredStreetIds
                                                            .contains(
                                                              opportunity
                                                                  .street
                                                                  .id,
                                                            );

                                                    return ListTile(
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                      dense: true,
                                                      title: Text(
                                                        opportunity
                                                                .street
                                                                .streetName
                                                                .isEmpty
                                                            ? 'Unnamed street'
                                                            : opportunity
                                                                  .street
                                                                  .streetName,
                                                      ),
                                                      subtitle: Text(
                                                        '${isCovered ? 'Covered' : 'Pending'} | ${opportunity.score.toStringAsFixed(0)} opportunity pts',
                                                      ),
                                                      trailing: IconButton(
                                                        icon: const Icon(
                                                          Icons
                                                              .center_focus_strong,
                                                        ),
                                                        tooltip: 'Pan map here',
                                                        onPressed: () =>
                                                            focusStreetWorkspace(
                                                              'mission',
                                                              opportunity
                                                                  .street,
                                                              message:
                                                                  'Mission map focused on this street.',
                                                            ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                              ],
                                            ],
                                            if (completedMissions
                                                .isNotEmpty) ...[
                                              const Divider(height: 24),
                                              const Text(
                                                'Completed missions',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              ...sortedCompletedMissions.take(5).map((
                                                mission,
                                              ) {
                                                final completedDate = mission
                                                    .completedAt
                                                    ?.toLocal();
                                                final historyLeads =
                                                    leadsForMission(mission);
                                                final historyMiles =
                                                    milesForMission(mission);
                                                final historyCovered =
                                                    coveredStreetCountForMission(
                                                      mission,
                                                    );
                                                final historyYield =
                                                    historyMiles == 0
                                                    ? 0.0
                                                    : historyLeads.length /
                                                          historyMiles;

                                                return ListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  dense: true,
                                                  title: Text(
                                                    completedDate == null
                                                        ? 'Completed mission'
                                                        : 'Completed ${completedDate.month}/${completedDate.day}/${completedDate.year}',
                                                  ),
                                                  subtitle: Text(
                                                    '$historyCovered/${mission.streetCount} streets | '
                                                    '${historyLeads.length} leads | '
                                                    '${historyYield.toStringAsFixed(2)} leads/mi',
                                                  ),
                                                  onTap: () => openMissionResults(
                                                    mission: mission,
                                                    areaName:
                                                        activeDriveArea?.name ??
                                                        'Drive Area',
                                                    leads: historyLeads,
                                                    streetsCovered:
                                                        historyCovered,
                                                    opportunityCaptured:
                                                        mission
                                                            .opportunityCaptured ??
                                                        0,
                                                    milesDriven: historyMiles,
                                                    actualMinutes:
                                                        mission.actualMinutes,
                                                    areaRemainingEstimatedMinutes:
                                                        estimatedMinutesForStreets(
                                                          activeAreaUncoveredStreets,
                                                        ),
                                                  ),
                                                );
                                              }),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 48,
                                      child: OutlinedButton(
                                        onPressed: markActiveDriveAreaComplete,
                                        child: const Text('Mark area complete'),
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (activeDriveArea != null)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Targets',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (isLoadingMarketProperties)
                                    const Text('Loading targets...')
                                  else ...[
                                    Text(
                                      '${filteredMarketProperties.length} of ${marketProperties.length} properties shown',
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        FilterChip(
                                          label: const Text('Out of state'),
                                          selected: targetFilterOutOfState,
                                          onSelected: (value) => setState(
                                            () =>
                                                targetFilterOutOfState = value,
                                          ),
                                        ),
                                        FilterChip(
                                          label: const Text('Absentee'),
                                          selected: targetFilterAbsentee,
                                          onSelected: (value) => setState(
                                            () => targetFilterAbsentee = value,
                                          ),
                                        ),
                                        FilterChip(
                                          label: const Text('Portfolio 3+'),
                                          selected: targetFilterPortfolio,
                                          onSelected: (value) => setState(
                                            () => targetFilterPortfolio = value,
                                          ),
                                        ),
                                        FilterChip(
                                          label: const Text('Low improvement'),
                                          selected: targetFilterLowImprovement,
                                          onSelected: (value) => setState(
                                            () => targetFilterLowImprovement =
                                                value,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Show only targets on map',
                                      ),
                                      value: showOnlyTargetsOnMap,
                                      onChanged: marketProperties.isEmpty
                                          ? null
                                          : (value) {
                                              setState(() {
                                                showOnlyTargetsOnMap = value;
                                              });
                                            },
                                    ),
                                    const SizedBox(height: 8),
                                    if (marketProperties.isEmpty)
                                      const Text(
                                        'Analyze this area to load its homes and targets.',
                                      )
                                    else if (filteredMarketProperties.isEmpty)
                                      const Text(
                                        'No targets match these filters.',
                                      )
                                    else
                                      ...filteredMarketProperties
                                          .take(25)
                                          .map(
                                            (property) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                property.parcel.displayAddress,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              subtitle: Text(
                                                [
                                                      if (property.outOfState)
                                                        'out of state',
                                                      if (property.absentee)
                                                        'absentee',
                                                      if (property
                                                              .portfolioCount >=
                                                          3)
                                                        'portfolio ${property.portfolioCount}',
                                                      if (property
                                                          .lowImprovementRatio)
                                                        'low improvement',
                                                    ].isEmpty
                                                    ? property
                                                              .parcel
                                                              .ownerName ??
                                                          'No signals'
                                                    : [
                                                        if (property
                                                                .parcel
                                                                .ownerName !=
                                                            null)
                                                          property
                                                              .parcel
                                                              .ownerName!,
                                                        [
                                                          if (property
                                                              .outOfState)
                                                            'out of state',
                                                          if (property.absentee)
                                                            'absentee',
                                                          if (property
                                                                  .portfolioCount >=
                                                              3)
                                                            'portfolio ${property.portfolioCount}',
                                                          if (property
                                                              .lowImprovementRatio)
                                                            'low improvement',
                                                        ].join(', '),
                                                      ].join(' | '),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              trailing: targetScoreBadge(
                                                property.targetScore,
                                                onTap: () =>
                                                    showTargetScoreBreakdown(
                                                      property,
                                                    ),
                                              ),
                                              onTap: () => openParcelPreview(
                                                property.parcel,
                                              ),
                                            ),
                                          ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        if (activeDriveArea != null) const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 900;
                            final summaryCard = Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Drive Summary',
                                            style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isTracking
                                                ? const Color(0xFFE8F5E9)
                                                : const Color(0xFFF3F4F6),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            isTracking ? 'Tracking' : 'Idle',
                                            style: TextStyle(
                                              color: isTracking
                                                  ? const Color(0xFF2E7D32)
                                                  : const Color(0xFF4B5563),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      isStreetCoverageLoading
                                          ? 'Loading saved coverage...'
                                          : hasStreetReferenceData
                                          ? '$selectedCoverageCity coverage and drive activity'
                                          : 'No street data loaded for $selectedCoverageCity yet.',
                                      style: const TextStyle(
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    _CoverageStatBlock(
                                      streetsDriven: coveredStreetCount,
                                      totalStreets: totalStreetCount,
                                      percent: streetCoveragePercent,
                                      milesCovered: totalMiles,
                                      totalMiles: estimatedCityStreetMiles,
                                      remainingStreets: remainingStreetCount,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Visible covered streets: $visibleCoveredStreetCount | Route points: $totalRoutePoints | Leads/mi: ${leadsPerMile.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Color(0xFF6B7280),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );

                            final actionsCard = Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Quick Actions',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'The basics you need while driving.',
                                      style: TextStyle(
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        icon: const Icon(Icons.add_home_work),
                                        onPressed: openAddLeadFromLocation,
                                        label: const Text(
                                          'Add Lead At My Location',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        icon: Icon(
                                          isTracking
                                              ? Icons.stop
                                              : Icons.play_arrow,
                                        ),
                                        onPressed: isTracking
                                            ? stopTracking
                                            : startTracking,
                                        label: Text(
                                          isTracking
                                              ? 'Stop Tracking'
                                              : 'Start Tracking',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.my_location),
                                        onPressed: isFindingLocation
                                            ? null
                                            : () => unawaited(findMyLocation()),
                                        label: Text(
                                          isFindingLocation
                                              ? 'Finding...'
                                              : 'Center On Me',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.public),
                                        onPressed: isTracking
                                            ? null
                                            : openMarketPicker,
                                        label: Text(
                                          'Market: $selectedCoverageCity',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );

                            if (!isWide) {
                              return Column(
                                children: [
                                  summaryCard,
                                  const SizedBox(height: 12),
                                  actionsCard,
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 2, child: summaryCard),
                                const SizedBox(width: 12),
                                Expanded(child: actionsCard),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                color: const Color(0xE6111827),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: handleFieldTestTitleTap,
                              child: Text(
                                activeDriveArea?.name ?? 'Market Coverage',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '·',
                              style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: isTracking
                                ? 'Stop tracking before changing markets'
                                : 'Search markets',
                            child: TextButton.icon(
                              icon: const Icon(Icons.search, size: 16),
                              label: Text(
                                activeCityLabel,
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                disabledForegroundColor: const Color(
                                  0xFF9CA3AF,
                                ),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                              ),
                              onPressed: isTracking ? null : openMarketPicker,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (driveAreas.length > 1 && !isDrawAreaMode)
            Positioned(
              top: 64,
              left: 12,
              child: SafeArea(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xE6FFFFFF),
                    foregroundColor: const Color(0xFF111827),
                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      showAllDriveAreaBoundaries = !showAllDriveAreaBoundaries;
                    });
                  },
                  child: Text(
                    showAllDriveAreaBoundaries
                        ? 'Active area only'
                        : 'Show all areas',
                  ),
                ),
              ),
            ),
          if (!isDrawAreaMode)
            Positioned(
              top: locationStatusTop,
              left: 12,
              right: 12,
              child: SafeArea(child: Align(child: buildLocationStatusPill())),
            ),
          if (hasNoDriveAreas && !isDrawAreaMode)
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 86, 18, 24),
                  child: Center(
                    child: _FirstDriveAreaWelcomeCard(
                      onDrawArea: enterDrawAreaMode,
                    ),
                  ),
                ),
              ),
            ),
          if (activeMission == null && !isDrawAreaMode && !hasNoDriveAreas)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  height: planPanelHeight,
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 18,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showFirstMissionTip) ...[
                        _FirstMissionTipCard(onDismiss: dismissFirstMissionTip),
                        const SizedBox(height: 10),
                      ],
                      Expanded(
                        child: todayScheduledMission == null
                            ? FilledButton.icon(
                                icon: const Icon(Icons.arrow_forward),
                                label: const Text("Plan Today's Drive"),
                                onPressed: () => openPlanTodayDriveSheet(
                                  streetOpportunities,
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          "Today's Planned Mission",
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        shortPlannerDateLabel(today),
                                        style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${activeDriveArea?.name ?? 'Drive Area'} - ${todayScheduledMission.streetCount} streets - ~$todayScheduledEstimatedMinutes min',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF374151),
                                    ),
                                  ),
                                  const Spacer(),
                                  FilledButton.icon(
                                    icon: const Icon(Icons.arrow_forward),
                                    label: const Text('Start Driving ->'),
                                    onPressed: isSavingMission
                                        ? null
                                        : () => startScheduledMission(
                                            todayScheduledMission,
                                          ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      TextButton(
                                        onPressed: () => skipScheduledMission(
                                          todayScheduledMission,
                                        ),
                                        child: const Text('Skip today'),
                                      ),
                                      const Text(
                                        '-',
                                        style: TextStyle(
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Adjust coming soon',
                                              ),
                                            ),
                                          );
                                        },
                                        child: const Text('Adjust'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            Positioned(
              top: 72,
              right: 12,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isMissionOverTimeBudget
                        ? const Color(0xFFFFF7ED)
                        : Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    '${missionPercent.toStringAsFixed(0)}% - $missionEstimatedMinutesRemaining min left',
                    style: TextStyle(
                      color: isMissionOverTimeBudget
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF111827),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 92,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => openMissionDetailSheet(
                    missionCoveredCount: missionCoveredCount,
                    missionStreetTotal: missionStreetTotal,
                    nextMissionStreet: nextMissionStreet,
                    missionEstimatedMinutesRemaining:
                        missionEstimatedMinutesRemaining,
                    missionOpportunityRemaining: missionOpportunityRemaining,
                    missionLeadsFound: missionLeadsFound,
                    missionMiles: missionMiles,
                    missionOpportunityCaptured: missionOpportunityCaptured,
                    hasMissionOpportunityScore: hasMissionOpportunityScore,
                  ),
                  child: Container(
                    height: 58,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Next: $nextStreetName - ${nextMissionStreet == null ? 0 : calibratedStreetMinutes(nextMissionStreet.street).ceil()} min',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 22,
              child: SafeArea(
                top: false,
                child: FloatingActionButton(
                  backgroundColor: const Color(0xFFF97316),
                  foregroundColor: Colors.white,
                  tooltip: 'Quick Capture',
                  onPressed: openQuickCaptureSheet,
                  child: const Icon(Icons.bolt),
                ),
              ),
            ),
          ],
          if (!isDrawAreaMode)
            Positioned(
              left: 12,
              bottom: findMeButtonBottom,
              child: SafeArea(top: false, child: buildFindMeFab()),
            ),
          if (activeMission == null && !isDrawAreaMode)
            Positioned(
              right: 16,
              bottom: todayScheduledMission == null ? 108 : 198,
              child: SafeArea(
                top: false,
                child: FloatingActionButton(
                  heroTag: 'drive-quick-capture-idle',
                  backgroundColor: const Color(0xFFF97316),
                  foregroundColor: Colors.white,
                  tooltip: 'Quick Capture',
                  onPressed: openQuickCaptureSheet,
                  child: const Icon(Icons.bolt),
                ),
              ),
            ),
          if (isDrawAreaMode)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: drawAreaMobileActionBar(),
            ),
        ],
      ),
    );
  }
}

/// Dialog that names a new drive area.
///
/// Owns the text and focus notifiers until the dialog widget unmounts, after
/// the close animation finishes.
class AreaNameDialog extends StatefulWidget {
  const AreaNameDialog({super.key});

  @override
  State<AreaNameDialog> createState() => _AreaNameDialogState();
}

class _AreaNameDialogState extends State<AreaNameDialog> {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  bool isClosing = false;

  void closeWith(String? value) {
    if (isClosing) return;
    isClosing = true;

    FocusScope.of(context).unfocus();
    focusNode.unfocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context).pop(value);
    });
  }

  @override
  void dispose() {
    focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save drive area'),
      content: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Area name'),
        onSubmitted: (value) => closeWith(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => closeWith(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => closeWith(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DriveStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _DriveStatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class MissionResultsSheet extends StatelessWidget {
  final Mission mission;
  final String areaName;
  final List<Lead> leads;
  final int streetsCovered;
  final double opportunityCaptured;
  final double milesDriven;
  final int? actualMinutes;
  final int areaRemainingEstimatedMinutes;
  final Future<void> Function(String leadId, String status) onUpdateLeadStatus;
  final Future<void> Function(String leadId, String source) onUpdateLeadSource;
  final Future<void> Function(String leadId, LeadScoreData scoreData)
  onUpdateLeadScoreData;
  final Future<void> Function(String leadId, LeadParcelData parcelData)
  onUpdateLeadParcelData;
  final Future<void> Function(String leadId, LeadReminderData reminderData)
  onUpdateLeadReminderData;
  final Future<void> Function(String leadId, LeadOfferData offerData)
  onUpdateLeadOfferData;

  const MissionResultsSheet({
    super.key,
    required this.mission,
    required this.areaName,
    required this.leads,
    required this.streetsCovered,
    required this.opportunityCaptured,
    required this.milesDriven,
    required this.actualMinutes,
    required this.areaRemainingEstimatedMinutes,
    required this.onUpdateLeadStatus,
    required this.onUpdateLeadSource,
    required this.onUpdateLeadScoreData,
    required this.onUpdateLeadParcelData,
    required this.onUpdateLeadReminderData,
    required this.onUpdateLeadOfferData,
  });

  void openLeadDetails(BuildContext context, Lead lead) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LeadDetailsScreen(
          lead: lead,
          onUpdateLeadStatus: onUpdateLeadStatus,
          onUpdateLeadSource: onUpdateLeadSource,
          onUpdateLeadScoreData: onUpdateLeadScoreData,
          onUpdateLeadParcelData: onUpdateLeadParcelData,
          onUpdateLeadReminderData: onUpdateLeadReminderData,
          onUpdateLeadOfferData: onUpdateLeadOfferData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final leadsPerMile = milesDriven == 0 ? 0.0 : leads.length / milesDriven;
    final completedAt = mission.completedAt?.toLocal();
    final opportunityPercent = mission.opportunityAtStart == 0
        ? 0.0
        : (opportunityCaptured / mission.opportunityAtStart) * 100;
    final plannedMinutes = mission.timeBudgetMinutes;
    final takenMinutes = actualMinutes ?? mission.actualMinutes;
    final sessionBudget = plannedMinutes ?? mission.estimatedMinutes ?? 30;
    final sessionsRemaining = sessionBudget <= 0
        ? 0
        : (areaRemainingEstimatedMinutes / sessionBudget).ceil();
    final priorityLeads = prioritizedMissionFollowUpLeads(leads);
    final topPriorityLeads = priorityLeads.take(3).toList(growable: false);

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mission recap',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          areaName,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                completedAt == null
                    ? 'Summary for this drive'
                    : 'Completed ${completedAt.month}/${completedAt.day}/${completedAt.year}',
                style: const TextStyle(color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _MissionResultMetric(
                              label: 'Leads',
                              value: leads.length.toString(),
                              icon: Icons.person_pin_circle,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _MissionResultMetric(
                              label: 'Leads / mile',
                              value: leadsPerMile.toStringAsFixed(2),
                              icon: Icons.timeline,
                              color: const Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _MissionResultMetric(
                              label: 'Streets',
                              value: streetsCovered.toString(),
                              icon: Icons.add_road,
                              color: const Color(0xFFF59E0B),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _MissionResultMetric(
                              label: 'Miles',
                              value: milesDriven.toStringAsFixed(2),
                              icon: Icons.route,
                              color: const Color(0xFF7C3AED),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _MissionResultMetric(
                              label: 'Planned',
                              value: plannedMinutes == null
                                  ? 'N/A'
                                  : '${plannedMinutes}m',
                              icon: Icons.schedule,
                              color: const Color(0xFF0F766E),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _MissionResultMetric(
                              label: 'Time taken',
                              value: takenMinutes == null
                                  ? 'N/A'
                                  : '${takenMinutes}m',
                              icon: Icons.timer,
                              color: const Color(0xFFEA580C),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF111827,
                          ).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.bolt, color: Color(0xFF111827)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Opportunity points captured',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${opportunityCaptured.toStringAsFixed(0)} pts (${opportunityPercent.clamp(0, 100).toStringAsFixed(0)}% of mission plan)',
                              style: const TextStyle(color: Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF2563EB,
                          ).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.event_available,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          areaRemainingEstimatedMinutes <= 0
                              ? 'This area is estimated complete.'
                              : 'Est. $sessionsRemaining more sessions at $sessionBudget min each to finish this area.',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF059669,
                              ).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.task_alt,
                              color: Color(0xFF059669),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Best next action',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  missionNextActionSummary(
                                    leadCount: leads.length,
                                    priorityLeadCount: priorityLeads.length,
                                    areaRemainingEstimatedMinutes:
                                        areaRemainingEstimatedMinutes,
                                  ),
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (topPriorityLeads.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ...topPriorityLeads.map(
                          (lead) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: SizedBox(
                              width: 42,
                              child: Center(
                                child: leadScoreBadge(lead.score, fontSize: 13),
                              ),
                            ),
                            title: Text(
                              leadPrimaryLabel(lead),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${normalizeLeadStage(lead.status)} - ${missionLeadFollowUpLabel(lead)}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => openLeadDetails(context, lead),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  title: Text('Attributed leads (${leads.length})'),
                  subtitle: const Text('Tap to review leads from this mission'),
                  children: leads.isEmpty
                      ? const [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                'No leads were attributed to this mission.',
                              ),
                            ),
                          ),
                        ]
                      : leads
                            .map(
                              (lead) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(leadPrimaryLabel(lead)),
                                subtitle: Text(
                                  '${leadSecondaryLabel(lead)}\nStage: ${normalizeLeadStage(lead.status)} | Score: ${lead.score}',
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => openLeadDetails(context, lead),
                              ),
                            )
                            .toList(growable: false),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissionResultMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MissionResultMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class AddLeadScreen extends StatefulWidget {
  final Future<void> Function(
    String address,
    String condition,
    String notes,
    String source,
    LeadScoreData scoreData,
    double? latitude,
    double? longitude, [
    String? missionId,
  ])
  onAddLead;

  final double? latitude;
  final double? longitude;
  final String? missionId;

  const AddLeadScreen({
    super.key,
    required this.onAddLead,
    this.latitude,
    this.longitude,
    this.missionId,
  });

  @override
  State<AddLeadScreen> createState() => _AddLeadScreenState();
}

class FieldTestLogScreen extends StatelessWidget {
  const FieldTestLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Test Log'),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: FieldTestLogger.plainText()),
              );
              if (!context.mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Field test log copied.')),
              );
            },
            child: const Text('Copy All'),
          ),
          TextButton(
            onPressed: () => FieldTestLogger.clear(),
            child: const Text('Clear Log'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: FieldTestLogger.revision,
        builder: (context, _, child) {
          final entries = FieldTestLogger.entries.reversed.toList();
          if (entries.isEmpty) {
            return const Center(child: Text('No field test events yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final timestamp = entry['timestamp'] ?? '';
              final event = entry['event'] ?? '';
              final detail = entry['detail'];

              return ListTile(
                dense: true,
                title: Text(event),
                subtitle: Text(
                  detail == null || detail.isEmpty
                      ? timestamp
                      : '$timestamp\n$detail',
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AddLeadScreenState extends State<AddLeadScreen> {
  final addressController = TextEditingController();
  final notesController = TextEditingController();
  String condition = 'Tall Grass';
  String source = 'Driving For Dollars';
  bool brokenWindows = false;
  bool roofDamage = false;
  bool tallGrass = false;
  bool trashInYard = false;
  bool exteriorWear = false;
  bool vacantAppearance = false;
  bool scoreOverride = false;
  double manualScore = 0;
  bool isSaving = false;

  @override
  void dispose() {
    addressController.dispose();
    notesController.dispose();
    super.dispose();
  }

  int get autoScore {
    // No parcel/sale data at capture time, so the records signals contribute 0
    // and the score reflects field-observed condition alone. It climbs once the
    // lead is enriched on the details screen.
    return calculateSmartLeadScore(
      vacantAppearance: vacantAppearance,
      roofDamage: roofDamage,
      trashInYard: trashInYard,
      brokenWindows: brokenWindows,
      tallGrass: tallGrass,
    );
  }

  LeadScoreData get scoreData {
    return LeadScoreData(
      brokenWindows: brokenWindows,
      roofDamage: roofDamage,
      tallGrass: tallGrass,
      trashInYard: trashInYard,
      exteriorWear: exteriorWear,
      vacantAppearance: vacantAppearance,
      score: scoreOverride ? manualScore.round() : autoScore,
      scoreOverride: scoreOverride,
    );
  }

  Future<void> saveLead() async {
    setState(() {
      isSaving = true;
    });

    final pendingBefore = await refreshPendingLeadsQueueCount();

    await widget.onAddLead(
      addressController.text,
      condition,
      notesController.text,
      source,
      scoreData,
      widget.latitude,
      widget.longitude,
      widget.missionId,
    );

    if (!mounted) return;

    final pendingAfter = await refreshPendingLeadsQueueCount();
    if (!mounted) return;

    if (pendingAfter > pendingBefore) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lead saved locally - will sync when connected.'),
        ),
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = widget.latitude != null && widget.longitude != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Lead')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              if (hasLocation)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Location saved: ${widget.latitude!.toStringAsFixed(5)}, ${widget.longitude!.toStringAsFixed(5)}',
                  ),
                ),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Property Address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: ValueKey(condition),
                initialValue: condition,
                decoration: const InputDecoration(
                  labelText: 'Condition',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Tall Grass',
                    child: Text('Tall Grass'),
                  ),
                  DropdownMenuItem(
                    value: 'Damaged Roof',
                    child: Text('Damaged Roof'),
                  ),
                  DropdownMenuItem(
                    value: 'Trash In Yard',
                    child: Text('Trash In Yard'),
                  ),
                  DropdownMenuItem(
                    value: 'Broken Windows',
                    child: Text('Broken Windows'),
                  ),
                  DropdownMenuItem(value: 'Vacant', child: Text('Vacant')),
                  DropdownMenuItem(
                    value: 'Excessive Wear',
                    child: Text('Excessive Wear'),
                  ),
                ],
                onChanged: isSaving
                    ? null
                    : (value) {
                        setState(() {
                          condition = value!;
                          if (condition == 'Broken Windows') {
                            brokenWindows = true;
                          } else if (condition == 'Damaged Roof') {
                            roofDamage = true;
                          } else if (condition == 'Tall Grass') {
                            tallGrass = true;
                          } else if (condition == 'Trash In Yard') {
                            trashInYard = true;
                          } else if (condition == 'Excessive Wear') {
                            exteriorWear = true;
                          } else if (condition == 'Vacant') {
                            vacantAppearance = true;
                          }
                        });
                      },
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: ValueKey(source),
                initialValue: source,
                decoration: const InputDecoration(
                  labelText: 'Source',
                  border: OutlineInputBorder(),
                ),
                items: leadSourceOptions
                    .map(
                      (sourceOption) => DropdownMenuItem(
                        value: sourceOption,
                        child: Text(sourceOption),
                      ),
                    )
                    .toList(),
                onChanged: isSaving
                    ? null
                    : (value) {
                        setState(() {
                          source = value!;
                        });
                      },
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Lead Score: ${scoreData.score}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: leadScoreColor(scoreData.score),
                              ),
                            ),
                          ),
                          Text(scoreOverride ? 'Manual' : 'Auto'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Broken windows'),
                        value: brokenWindows,
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  brokenWindows = value ?? false;
                                });
                              },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Roof damage'),
                        value: roofDamage,
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  roofDamage = value ?? false;
                                });
                              },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Tall grass'),
                        value: tallGrass,
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  tallGrass = value ?? false;
                                });
                              },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Trash in yard'),
                        value: trashInYard,
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  trashInYard = value ?? false;
                                });
                              },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Vacant appearance'),
                        value: vacantAppearance,
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  vacantAppearance = value ?? false;
                                });
                              },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Manual score override'),
                        value: scoreOverride,
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  scoreOverride = value;
                                  manualScore = autoScore.toDouble();
                                });
                              },
                      ),
                      if (scoreOverride)
                        Slider(
                          min: 0,
                          max: 100,
                          divisions: 100,
                          label: manualScore.round().toString(),
                          value: manualScore,
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  setState(() {
                                    manualScore = value;
                                  });
                                },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: notesController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: isSaving ? null : saveLead,
                  child: Text(
                    isSaving ? 'Saving...' : 'Save Lead',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LeadListScreen extends StatefulWidget {
  final List<Lead> leads;
  final ValueListenable<int> pendingSyncCountListenable;
  final Future<void> Function(String leadId, String status) onUpdateLeadStatus;
  final Future<void> Function(String leadId, String source) onUpdateLeadSource;
  final Future<void> Function(String leadId, LeadScoreData scoreData)
  onUpdateLeadScoreData;
  final Future<void> Function(String leadId, LeadParcelData parcelData)
  onUpdateLeadParcelData;
  final Future<void> Function(String leadId, LeadReminderData reminderData)
  onUpdateLeadReminderData;
  final Future<void> Function(String leadId, LeadOfferData offerData)
  onUpdateLeadOfferData;

  const LeadListScreen({
    super.key,
    required this.leads,
    required this.pendingSyncCountListenable,
    required this.onUpdateLeadStatus,
    required this.onUpdateLeadSource,
    required this.onUpdateLeadScoreData,
    required this.onUpdateLeadParcelData,
    required this.onUpdateLeadReminderData,
    required this.onUpdateLeadOfferData,
  });

  @override
  State<LeadListScreen> createState() => _LeadListScreenState();
}

class _LeadListScreenState extends State<LeadListScreen> {
  final searchController = TextEditingController();
  String searchQuery = '';
  String stageFilter = 'All';
  String sourceFilter = 'All';
  String revisitFilter = 'All';
  String propertySignalFilter = 'All';
  String sortMode = 'Score high to low';
  double minScoreFilter = 0;
  double maxScoreFilter = 100;
  bool showAdvancedFilters = false;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void resetFilters() {
    setState(() {
      searchQuery = '';
      searchController.clear();
      stageFilter = 'All';
      sourceFilter = 'All';
      revisitFilter = 'All';
      propertySignalFilter = 'All';
      sortMode = 'Score high to low';
      minScoreFilter = 0;
      maxScoreFilter = 100;
    });
  }

  bool leadMatchesRevisitFilter(Lead lead) {
    final today = DateTime.now();
    final reminderDate = lead.reminderData.reminderDate;

    return switch (revisitFilter) {
      'Needs revisit' => lead.reminderData.followUpStatus == 'Needs Revisit',
      'Scheduled' => lead.reminderData.followUpStatus == 'Scheduled',
      'Due today' => isSameDate(reminderDate, today),
      'Overdue' => isBeforeDate(reminderDate, today),
      'No reminder' => reminderDate == null,
      _ => true,
    };
  }

  bool leadMatchesPropertySignalFilter(Lead lead) {
    return switch (propertySignalFilter) {
      'Out-of-state owner' => lead.parcelData.outOfStateOwner,
      'Has owner name' => lead.parcelData.ownerName.trim().isNotEmpty,
      'Has mailing address' => lead.parcelData.mailingAddress.trim().isNotEmpty,
      'Has ARV/MAO' => lead.offerData.arv != null || lead.offerData.mao != null,
      'Has location' => lead.latitude != null && lead.longitude != null,
      'Hot score 70+' => lead.score >= 70,
      _ => true,
    };
  }

  int get activeFilterCount {
    var count = 0;
    if (searchQuery.trim().isNotEmpty) count++;
    if (stageFilter != 'All') count++;
    if (sourceFilter != 'All') count++;
    if (revisitFilter != 'All') count++;
    if (propertySignalFilter != 'All') count++;
    if (minScoreFilter > 0 || maxScoreFilter < 100) count++;
    if (sortMode != 'Score high to low') count++;
    return count;
  }

  Future<void> exportLeadsCsv(List<Lead> leads) async {
    await Clipboard.setData(ClipboardData(text: leadsToCsv(leads)));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied ${leads.length} leads as CSV to the clipboard.'),
      ),
    );
  }

  void openLeadDetails(Lead lead) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LeadDetailsScreen(
          lead: lead,
          onUpdateLeadStatus: (leadId, status) async {
            await widget.onUpdateLeadStatus(leadId, status);

            if (mounted) {
              setState(() {});
            }
          },
          onUpdateLeadSource: (leadId, source) async {
            await widget.onUpdateLeadSource(leadId, source);

            if (mounted) {
              setState(() {});
            }
          },
          onUpdateLeadScoreData: (leadId, scoreData) async {
            await widget.onUpdateLeadScoreData(leadId, scoreData);

            if (mounted) {
              setState(() {});
            }
          },
          onUpdateLeadParcelData: (leadId, parcelData) async {
            await widget.onUpdateLeadParcelData(leadId, parcelData);

            if (mounted) {
              setState(() {});
            }
          },
          onUpdateLeadReminderData: (leadId, reminderData) async {
            await widget.onUpdateLeadReminderData(leadId, reminderData);

            if (mounted) {
              setState(() {});
            }
          },
          onUpdateLeadOfferData: (leadId, offerData) async {
            await widget.onUpdateLeadOfferData(leadId, offerData);

            if (mounted) {
              setState(() {});
            }
          },
        ),
      ),
    );
  }

  Widget leadResultsList(List<Lead> filteredLeads, {required bool scroll}) {
    if (filteredLeads.isEmpty) {
      return Card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.manage_search,
                  size: 48,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No matching leads',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Adjust the search or pipeline filter.',
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!scroll) {
      return Column(
        children: [
          for (var index = 0; index < filteredLeads.length; index++) ...[
            _LeadListRow(
              lead: filteredLeads[index],
              onTap: () => openLeadDetails(filteredLeads[index]),
            ),
            if (index != filteredLeads.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
    }

    return ListView.separated(
      itemCount: filteredLeads.length,
      padding: EdgeInsets.zero,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final lead = filteredLeads[index];

        return _LeadListRow(lead: lead, onTap: () => openLeadDetails(lead));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedLeads = [...widget.leads];
    final stages = <String>{
      'All',
      ...sortedLeads.map((lead) => normalizeLeadStage(lead.status)),
    }.toList();
    final sources = <String>{
      'All',
      ...leadSourceOptions,
      ...sortedLeads
          .map((lead) => lead.source)
          .where((source) => source.isNotEmpty),
    }.toList();
    final normalizedQuery = searchQuery.trim().toLowerCase();
    final filteredLeads = sortedLeads
        .where((lead) {
          final stage = normalizeLeadStage(lead.status);
          final matchesStage = stageFilter == 'All' || stage == stageFilter;
          final matchesSource =
              sourceFilter == 'All' || lead.source == sourceFilter;
          final matchesScore =
              lead.score >= minScoreFilter.round() &&
              lead.score <= maxScoreFilter.round();
          final matchesSearch =
              normalizedQuery.isEmpty ||
              leadPrimaryLabel(lead).toLowerCase().contains(normalizedQuery) ||
              leadSecondaryLabel(
                lead,
              ).toLowerCase().contains(normalizedQuery) ||
              lead.address.toLowerCase().contains(normalizedQuery) ||
              lead.parcelData.ownerName.toLowerCase().contains(
                normalizedQuery,
              ) ||
              lead.source.toLowerCase().contains(normalizedQuery) ||
              lead.condition.toLowerCase().contains(normalizedQuery) ||
              lead.notes.toLowerCase().contains(normalizedQuery);

          return matchesStage &&
              matchesSource &&
              matchesScore &&
              matchesSearch &&
              leadMatchesRevisitFilter(lead) &&
              leadMatchesPropertySignalFilter(lead);
        })
        .toList(growable: false);
    filteredLeads.sort((a, b) {
      return switch (sortMode) {
        'Score low to high' => a.score.compareTo(b.score),
        'Newest first' =>
          (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
        'Oldest first' =>
          (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
        'Owner A-Z' => leadPrimaryLabel(a).compareTo(leadPrimaryLabel(b)),
        'Stage A-Z' => normalizeLeadStage(
          a.status,
        ).compareTo(normalizeLeadStage(b.status)),
        _ => b.score.compareTo(a.score),
      };
    });
    final hotLeads = sortedLeads.where((lead) => lead.score >= 70).length;
    final avgScore = sortedLeads.isEmpty
        ? 0
        : sortedLeads.fold<int>(0, (total, lead) => total + lead.score) /
              sortedLeads.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leads'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Copy leads as CSV',
            onPressed: filteredLeads.isEmpty
                ? null
                : () => exportLeadsCsv(filteredLeads),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 700;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lead command center',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Find the right property, prioritize the highest scores, and move deals forward.',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: filteredLeads.isEmpty
                        ? null
                        : () => exportLeadsCsv(filteredLeads),
                    icon: const Icon(Icons.download),
                    label: const Text('Export CSV'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<int>(
                valueListenable: widget.pendingSyncCountListenable,
                builder: (context, pendingCount, _) {
                  if (pendingCount == 0) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF97316)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.sync_problem,
                                  size: 18,
                                  color: Color(0xFFC2410C),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$pendingCount lead${pendingCount == 1 ? '' : 's'} pending sync',
                                  style: const TextStyle(
                                    color: Color(0xFF9A3412),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: pendingLeadRows(),
                              builder: (context, snapshot) {
                                final rows =
                                    snapshot.data ??
                                    const <Map<String, dynamic>>[];
                                if (rows.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                final previewRows = rows.take(3).toList();

                                return Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    left: 26,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ...previewRows.map(
                                        (row) => Text(
                                          row['address']
                                                      ?.toString()
                                                      .isNotEmpty ==
                                                  true
                                              ? row['address'].toString()
                                              : 'Unsynced lead',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF9A3412),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      if (rows.length > previewRows.length)
                                        Text(
                                          '+${rows.length - previewRows.length} more',
                                          style: const TextStyle(
                                            color: Color(0xFF9A3412),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth > 900 ? 4 : 2;
                  final width =
                      (constraints.maxWidth - ((columns - 1) * 12)) / columns;

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: width,
                        child: _LeadSummaryCard(
                          label: 'Visible leads',
                          value: filteredLeads.length.toString(),
                          icon: Icons.visibility,
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _LeadSummaryCard(
                          label: 'Total leads',
                          value: sortedLeads.length.toString(),
                          icon: Icons.home_work,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _LeadSummaryCard(
                          label: 'Hot leads',
                          value: hotLeads.toString(),
                          icon: Icons.local_fire_department,
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _LeadSummaryCard(
                          label: 'Avg score',
                          value: avgScore.toStringAsFixed(0),
                          icon: Icons.speed,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 900;
                          final searchField = TextField(
                            controller: searchController,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              labelText: 'Search owner, address, source, notes',
                            ),
                            onChanged: (value) {
                              setState(() {
                                searchQuery = value;
                              });
                            },
                          );
                          final stageField = DropdownButtonFormField<String>(
                            initialValue: stages.contains(stageFilter)
                                ? stageFilter
                                : 'All',
                            decoration: const InputDecoration(
                              labelText: 'Pipeline stage',
                            ),
                            items: stages
                                .map(
                                  (stage) => DropdownMenuItem(
                                    value: stage,
                                    child: Text(stage),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                stageFilter = value ?? 'All';
                              });
                            },
                          );
                          final sortField = DropdownButtonFormField<String>(
                            initialValue: sortMode,
                            decoration: const InputDecoration(
                              labelText: 'Sort',
                            ),
                            items:
                                const [
                                      'Score high to low',
                                      'Score low to high',
                                      'Newest first',
                                      'Oldest first',
                                      'Owner A-Z',
                                      'Stage A-Z',
                                    ]
                                    .map(
                                      (sort) => DropdownMenuItem(
                                        value: sort,
                                        child: Text(sort),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (value) {
                              setState(() {
                                sortMode = value ?? 'Score high to low';
                              });
                            },
                          );

                          if (!isWide) {
                            return Column(
                              children: [
                                searchField,
                                const SizedBox(height: 10),
                                stageField,
                                const SizedBox(height: 10),
                                sortField,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(flex: 2, child: searchField),
                              const SizedBox(width: 10),
                              Expanded(child: stageField),
                              const SizedBox(width: 10),
                              Expanded(child: sortField),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Chip(
                                  avatar: const Icon(
                                    Icons.filter_list,
                                    size: 18,
                                  ),
                                  label: Text(
                                    '$activeFilterCount active filters',
                                  ),
                                ),
                                Text(
                                  '${filteredLeads.length} of ${sortedLeads.length} leads shown',
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: activeFilterCount == 0
                                ? null
                                : resetFilters,
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('Reset'),
                          ),
                          IconButton(
                            tooltip: showAdvancedFilters
                                ? 'Hide advanced filters'
                                : 'Show advanced filters',
                            onPressed: () {
                              setState(() {
                                showAdvancedFilters = !showAdvancedFilters;
                              });
                            },
                            icon: Icon(
                              showAdvancedFilters
                                  ? Icons.expand_less
                                  : Icons.tune,
                            ),
                          ),
                        ],
                      ),
                      if (showAdvancedFilters) ...[
                        const Divider(height: 22),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 900;
                            final sourceField = DropdownButtonFormField<String>(
                              initialValue: sources.contains(sourceFilter)
                                  ? sourceFilter
                                  : 'All',
                              decoration: const InputDecoration(
                                labelText: 'Lead source',
                              ),
                              items: sources
                                  .map(
                                    (source) => DropdownMenuItem(
                                      value: source,
                                      child: Text(source),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  sourceFilter = value ?? 'All';
                                });
                              },
                            );
                            final revisitField =
                                DropdownButtonFormField<String>(
                                  initialValue: revisitFilter,
                                  decoration: const InputDecoration(
                                    labelText: 'Revisit status',
                                  ),
                                  items:
                                      const [
                                            'All',
                                            'Needs revisit',
                                            'Scheduled',
                                            'Due today',
                                            'Overdue',
                                            'No reminder',
                                          ]
                                          .map(
                                            (filter) => DropdownMenuItem(
                                              value: filter,
                                              child: Text(filter),
                                            ),
                                          )
                                          .toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      revisitFilter = value ?? 'All';
                                    });
                                  },
                                );
                            final signalField = DropdownButtonFormField<String>(
                              initialValue: propertySignalFilter,
                              decoration: const InputDecoration(
                                labelText: 'Property signal',
                              ),
                              items:
                                  const [
                                        'All',
                                        'Out-of-state owner',
                                        'Has owner name',
                                        'Has mailing address',
                                        'Has ARV/MAO',
                                        'Has location',
                                        'Hot score 70+',
                                      ]
                                      .map(
                                        (filter) => DropdownMenuItem(
                                          value: filter,
                                          child: Text(filter),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) {
                                setState(() {
                                  propertySignalFilter = value ?? 'All';
                                });
                              },
                            );
                            final scoreFilter = Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFD1D5DB),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Score ${minScoreFilter.round()}-${maxScoreFilter.round()}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  RangeSlider(
                                    min: 0,
                                    max: 100,
                                    divisions: 20,
                                    labels: RangeLabels(
                                      minScoreFilter.round().toString(),
                                      maxScoreFilter.round().toString(),
                                    ),
                                    values: RangeValues(
                                      minScoreFilter,
                                      maxScoreFilter,
                                    ),
                                    onChanged: (values) {
                                      setState(() {
                                        minScoreFilter = values.start;
                                        maxScoreFilter = values.end;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            );

                            if (!isWide) {
                              return Column(
                                children: [
                                  sourceField,
                                  const SizedBox(height: 10),
                                  revisitField,
                                  const SizedBox(height: 10),
                                  signalField,
                                  const SizedBox(height: 10),
                                  scoreFilter,
                                ],
                              );
                            }

                            return Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: sourceField),
                                    const SizedBox(width: 10),
                                    Expanded(child: revisitField),
                                    const SizedBox(width: 10),
                                    Expanded(child: signalField),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                scoreFilter,
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (isMobile)
                leadResultsList(filteredLeads, scroll: false)
              else
                Expanded(child: leadResultsList(filteredLeads, scroll: true)),
            ],
          );

          if (isMobile) {
            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: content,
              ),
            );
          }

          return Padding(padding: const EdgeInsets.all(20), child: content);
        },
      ),
    );
  }
}

class _LeadSummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _LeadSummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadListRow extends StatelessWidget {
  final Lead lead;
  final VoidCallback onTap;

  const _LeadListRow({required this.lead, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final stage = normalizeLeadStage(lead.status);
    final lastSaleDate = lead.saleData.lastSaleDate.isEmpty
        ? 'No sale date'
        : lead.saleData.lastSaleDate;
    final primaryLabel = leadPrimaryLabel(lead);
    final secondaryLabel = leadSecondaryLabel(lead);
    final condition = lead.condition.trim();
    final detailLine = condition.isEmpty || secondaryLabel == condition
        ? secondaryLabel
        : '$secondaryLabel | $condition';
    final infoChips = [
      leadStageBadge(stage),
      _MiniInfoChip(
        icon: Icons.sell,
        label: '$lastSaleDate ${formatMoney(lead.saleData.lastSalePrice)}',
      ),
      _MiniInfoChip(
        icon: Icons.calculate,
        label: 'MAO ${formatMoney(lead.mao)}',
      ),
    ];
    final scoreBox = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: leadScoreColor(lead.score).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          lead.score.toString(),
          style: TextStyle(
            color: leadScoreColor(lead.score),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          primaryLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          detailLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF6B7280)),
        ),
      ],
    );

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 520;
            final chips = Wrap(spacing: 8, runSpacing: 8, children: infoChips);

            if (isCompact) {
              return Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        scoreBox,
                        const SizedBox(width: 12),
                        Expanded(child: titleBlock),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF9CA3AF),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    chips,
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  scoreBox,
                  const SizedBox(width: 14),
                  Expanded(flex: 3, child: titleBlock),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: chips),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MiniInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniInfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF6B7280)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF374151), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LeadDetailsScreen extends StatefulWidget {
  final Lead lead;
  final Future<void> Function(String leadId, String status) onUpdateLeadStatus;
  final Future<void> Function(String leadId, String source) onUpdateLeadSource;
  final Future<void> Function(String leadId, LeadScoreData scoreData)
  onUpdateLeadScoreData;
  final Future<void> Function(String leadId, LeadParcelData parcelData)
  onUpdateLeadParcelData;
  final Future<void> Function(String leadId, LeadReminderData reminderData)
  onUpdateLeadReminderData;
  final Future<void> Function(String leadId, LeadOfferData offerData)
  onUpdateLeadOfferData;

  const LeadDetailsScreen({
    super.key,
    required this.lead,
    required this.onUpdateLeadStatus,
    required this.onUpdateLeadSource,
    required this.onUpdateLeadScoreData,
    required this.onUpdateLeadParcelData,
    required this.onUpdateLeadReminderData,
    required this.onUpdateLeadOfferData,
  });

  @override
  State<LeadDetailsScreen> createState() => _LeadDetailsScreenState();
}

class _LeadDetailsScreenState extends State<LeadDetailsScreen> {
  final ImagePicker imagePicker = ImagePicker();
  final ownerNameController = TextEditingController();
  final mailingAddressController = TextEditingController();
  final assessedValueController = TextEditingController();
  final propertyTypeController = TextEditingController();
  final lotSizeController = TextEditingController();
  final yearBuiltController = TextEditingController();
  final arvController = TextEditingController();
  final repairCostController = TextEditingController();
  final assignmentFeeController = TextEditingController();

  late String status;
  late String source;
  late LeadScoreData scoreData;
  late LeadReminderData reminderData;
  late bool outOfStateOwner;
  List<LeadPhoto> photos = [];
  bool isSavingStatus = false;
  bool isSavingSource = false;
  bool isSavingScore = false;
  bool isSavingParcel = false;
  bool isSavingReminder = false;
  bool isSavingOffer = false;
  bool isLoadingPhotos = true;
  bool isUploadingPhoto = false;
  String? missionAttributionLabel;

  @override
  void initState() {
    super.initState();
    status = normalizeLeadStage(widget.lead.status);
    source = widget.lead.source;
    scoreData = widget.lead.scoreData;
    reminderData = widget.lead.reminderData;
    ownerNameController.text = widget.lead.parcelData.ownerName;
    mailingAddressController.text = widget.lead.parcelData.mailingAddress;
    assessedValueController.text =
        widget.lead.parcelData.assessedValue?.toStringAsFixed(0) ?? '';
    propertyTypeController.text = widget.lead.parcelData.propertyType;
    lotSizeController.text = widget.lead.parcelData.lotSize;
    yearBuiltController.text =
        widget.lead.parcelData.yearBuilt?.toString() ?? '';
    arvController.text = widget.lead.offerData.arv?.toStringAsFixed(0) ?? '';
    repairCostController.text =
        widget.lead.offerData.repairCost?.toStringAsFixed(0) ?? '';
    assignmentFeeController.text =
        widget.lead.offerData.assignmentFee?.toStringAsFixed(0) ?? '';
    outOfStateOwner = widget.lead.parcelData.outOfStateOwner;
    loadLeadPhotos();
    loadMissionAttribution();
  }

  @override
  void dispose() {
    ownerNameController.dispose();
    mailingAddressController.dispose();
    assessedValueController.dispose();
    propertyTypeController.dispose();
    lotSizeController.dispose();
    yearBuiltController.dispose();
    arvController.dispose();
    repairCostController.dispose();
    assignmentFeeController.dispose();
    super.dispose();
  }

  String photoExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');

    if (dotIndex == -1) return '.jpg';

    final extension = fileName.substring(dotIndex).toLowerCase();
    const allowedExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.heic'];

    return allowedExtensions.contains(extension) ? extension : '.jpg';
  }

  String photoContentType(String fileName) {
    switch (photoExtension(fileName)) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.jpg':
      case '.jpeg':
      default:
        return 'image/jpeg';
    }
  }

  String photoStorageErrorMessage(Object error) {
    final details = error.toString();
    final lowerDetails = details.toLowerCase();

    if (lowerDetails.contains('bucket') && lowerDetails.contains('not found')) {
      return 'Photo storage is not set up yet. Run the latest Supabase photo storage migration, then try again.';
    }

    if (lowerDetails.contains('row-level security') ||
        lowerDetails.contains('rls') ||
        lowerDetails.contains('unauthorized') ||
        lowerDetails.contains('403') ||
        lowerDetails.contains('401')) {
      return 'Photo upload is blocked by storage permissions. Run the latest Supabase security migration, then try again.';
    }

    if (lowerDetails.contains('payload too large') ||
        lowerDetails.contains('file size') ||
        lowerDetails.contains('max allowed') ||
        lowerDetails.contains('too large')) {
      return 'Photo is too large. Choose a smaller image or lower camera resolution.';
    }

    if (lowerDetails.contains('not signed in') ||
        lowerDetails.contains('sign in again')) {
      return 'You are not signed in. Sign in again, then retry.';
    }

    return 'Could not upload photo. Please try again.';
  }

  void showPhotoError(Object error) {
    final message = photoStorageErrorMessage(error);
    if (kDebugMode) {
      debugPrint('Lead photo error: $error');
      unawaited(
        FieldTestLogger.log('lead_photo_error', detail: error.toString()),
      );
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
    );
  }

  Future<String> leadPhotoStorageFolder() async {
    if (supabase.auth.currentSession == null) {
      await supabase.auth.refreshSession();
    }

    final userId = supabase.auth.currentUser?.id;

    if (userId == null || userId.isEmpty) {
      throw StateError('You are not signed in. Sign in again, then retry.');
    }

    return '$userId/${widget.lead.id}';
  }

  Future<void> loadLeadPhotos() async {
    setState(() {
      isLoadingPhotos = true;
    });

    try {
      final storageFolder = await leadPhotoStorageFolder();
      final files = await supabase.storage
          .from(leadPhotosBucket)
          .list(path: storageFolder);

      final loadedPhotos = await Future.wait(
        files.where((file) => file.name.isNotEmpty).map((file) async {
          final path = '$storageFolder/${file.name}';
          final signedUrl = await supabase.storage
              .from(leadPhotosBucket)
              .createSignedUrl(path, leadPhotoSignedUrlSeconds);

          return LeadPhoto(path: path, url: signedUrl);
        }),
      );

      if (!mounted) return;

      setState(() {
        photos = loadedPhotos;
        isLoadingPhotos = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isLoadingPhotos = false;
      });

      showPhotoError(error);
    }
  }

  Future<void> loadMissionAttribution() async {
    try {
      final leadRows = await supabase
          .from('leads')
          .select('mission_id')
          .eq('id', widget.lead.id)
          .limit(1);

      if (leadRows.isEmpty) return;

      final missionId = leadRows.first['mission_id']?.toString();
      if (missionId == null || missionId.isEmpty) return;

      final missionRows = await supabase
          .from('missions')
          .select('drive_area_id,created_at,started_at')
          .eq('id', missionId)
          .limit(1);

      if (missionRows.isEmpty) return;

      final mission = missionRows.first;
      final areaId = mission['drive_area_id']?.toString();
      var areaName = 'mission';

      if (areaId != null && areaId.isNotEmpty) {
        final areaRows = await supabase
            .from('drive_areas')
            .select('name')
            .eq('id', areaId)
            .limit(1);

        if (areaRows.isNotEmpty) {
          areaName = areaRows.first['name']?.toString() ?? areaName;
        }
      }

      final missionDate = DateTime.tryParse(
        (mission['started_at'] ?? mission['created_at'] ?? '').toString(),
      )?.toLocal();

      if (!mounted) return;

      setState(() {
        missionAttributionLabel = missionDate == null
            ? 'Attributed to: $areaName'
            : 'Attributed to: $areaName (${missionDate.month}/${missionDate.day}/${missionDate.year})';
      });
    } catch (_) {
      // Attribution is read-only context; never block lead details.
    }
  }

  Future<void> uploadLeadPhoto() async {
    XFile? pickedPhoto;

    try {
      pickedPhoto = await imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 2048,
        maxHeight: 2048,
      );
    } catch (error) {
      showPhotoError(error);
      return;
    }

    if (pickedPhoto == null) return;

    setState(() {
      isUploadingPhoto = true;
    });

    try {
      final storageFolder = await leadPhotoStorageFolder();
      final photoSize = await pickedPhoto.length();

      if (photoSize > maxLeadPhotoBytes) {
        throw StateError(
          'Selected photo is ${(photoSize / (1024 * 1024)).toStringAsFixed(1)} MB. Max allowed is 10 MB.',
        );
      }

      final photoBytes = await pickedPhoto.readAsBytes().timeout(
        const Duration(seconds: 30),
      );
      final extension = photoExtension(pickedPhoto.name);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}$extension';
      final storagePath = '$storageFolder/$fileName';
      final contentType = pickedPhoto.mimeType ?? photoContentType(fileName);
      final userId = supabase.auth.currentUser?.id ?? 'none';
      final hasSession = supabase.auth.currentSession != null;

      if (kDebugMode) {
        debugPrint(
          'Lead photo upload start: lead=${widget.lead.id}, user=$userId, '
          'session=$hasSession, bytes=$photoSize, type=$contentType, '
          'path=$storagePath',
        );

        unawaited(
          FieldTestLogger.log(
            'lead_photo_upload_start',
            detail:
                'lead=${widget.lead.id}, user=$userId, session=$hasSession, bytes=$photoSize, type=$contentType, path=$storagePath',
          ),
        );
      }

      await supabase.storage
          .from(leadPhotosBucket)
          .uploadBinary(
            storagePath,
            photoBytes,
            fileOptions: FileOptions(contentType: contentType),
          )
          .timeout(const Duration(seconds: 45));

      await loadLeadPhotos();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo uploaded.')));
    } catch (error) {
      showPhotoError(error);
    } finally {
      if (mounted) {
        setState(() {
          isUploadingPhoto = false;
        });
      }
    }
  }

  Future<void> updateStatus(String? value) async {
    if (value == null || value == status) return;

    final previousStatus = status;

    setState(() {
      status = value;
      isSavingStatus = true;
    });

    try {
      await widget.onUpdateLeadStatus(widget.lead.id, value);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pipeline stage updated to $value')),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        status = previousStatus;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update pipeline stage.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSavingStatus = false;
        });
      }
    }
  }

  Future<void> updateSource(String? value) async {
    if (value == null || value == source) return;

    final previousSource = source;

    setState(() {
      source = value;
      isSavingSource = true;
    });

    try {
      await widget.onUpdateLeadSource(widget.lead.id, value);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Source updated to $value')));
    } catch (_) {
      if (!mounted) return;

      setState(() {
        source = previousSource;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not update source.')));
    } finally {
      if (mounted) {
        setState(() {
          isSavingSource = false;
        });
      }
    }
  }

  LeadScoreData scoreDataWithAutoScore({
    bool? brokenWindows,
    bool? roofDamage,
    bool? tallGrass,
    bool? trashInYard,
    bool? exteriorWear,
    bool? vacantAppearance,
    bool? scoreOverride,
    int? score,
  }) {
    final updatedScoreData = scoreData.copyWith(
      brokenWindows: brokenWindows,
      roofDamage: roofDamage,
      tallGrass: tallGrass,
      trashInYard: trashInYard,
      exteriorWear: exteriorWear,
      vacantAppearance: vacantAppearance,
      scoreOverride: scoreOverride,
      score: score,
    );

    if (updatedScoreData.scoreOverride) return updatedScoreData;

    return updatedScoreData.copyWith(
      score: recomputeAutoScore(updatedScoreData),
    );
  }

  /// Recomputes the smart distressed-seller score from field-observed condition
  /// plus whatever public-records data this lead currently has. Missing records
  /// simply contribute 0.
  int recomputeAutoScore(LeadScoreData s) {
    return calculateSmartLeadScore(
      vacantAppearance: s.vacantAppearance,
      roofDamage: s.roofDamage,
      trashInYard: s.trashInYard,
      brokenWindows: s.brokenWindows,
      tallGrass: s.tallGrass,
      outOfStateOwner: outOfStateOwner,
      mailingAddress: mailingAddressController.text,
      propertyAddress: widget.lead.address,
      lastSaleDate: widget.lead.saleData.lastSaleDate,
      assessedValue:
          parseMoney(assessedValueController.text) ??
          widget.lead.parcelData.assessedValue,
    );
  }

  Future<void> updateScoreData(LeadScoreData updatedScoreData) async {
    final previousScoreData = scoreData;

    setState(() {
      scoreData = updatedScoreData;
      isSavingScore = true;
    });

    try {
      await widget.onUpdateLeadScoreData(widget.lead.id, updatedScoreData);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Score updated to ${updatedScoreData.score}')),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        scoreData = previousScoreData;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not update score.')));
    } finally {
      if (mounted) {
        setState(() {
          isSavingScore = false;
        });
      }
    }
  }

  double? parseMoney(String value) {
    final cleanedValue = value.replaceAll(',', '').replaceAll(r'$', '').trim();

    if (cleanedValue.isEmpty) return null;

    return double.tryParse(cleanedValue);
  }

  int? parseYearBuilt(String value) {
    final cleanedValue = value.trim();

    if (cleanedValue.isEmpty) return null;

    return int.tryParse(cleanedValue);
  }

  LeadOfferData currentOfferData() {
    return LeadOfferData(
      arv: parseMoney(arvController.text),
      repairCost: parseMoney(repairCostController.text),
      assignmentFee: parseMoney(assignmentFeeController.text),
    );
  }

  Future<void> saveOfferDetails() async {
    final offerData = currentOfferData();

    setState(() {
      isSavingOffer = true;
    });

    try {
      await widget.onUpdateLeadOfferData(widget.lead.id, offerData);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Offer numbers saved.')));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save offer numbers.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSavingOffer = false;
        });
      }
    }
  }

  Future<void> saveParcelDetails() async {
    final parcelData = LeadParcelData(
      ownerName: ownerNameController.text.trim(),
      mailingAddress: mailingAddressController.text.trim(),
      outOfStateOwner: outOfStateOwner,
      assessedValue: parseMoney(assessedValueController.text),
      propertyType: propertyTypeController.text.trim(),
      lotSize: lotSizeController.text.trim(),
      yearBuilt: parseYearBuilt(yearBuiltController.text),
    );

    setState(() {
      isSavingParcel = true;
    });

    try {
      await widget.onUpdateLeadParcelData(widget.lead.id, parcelData);

      // Property records feed the smart score, so refresh it after saving
      // (unless the score is manually overridden).
      if (!scoreData.scoreOverride) {
        final rescored = scoreData.copyWith(
          score: recomputeAutoScore(scoreData),
        );

        if (rescored.score != scoreData.score) {
          await widget.onUpdateLeadScoreData(widget.lead.id, rescored);

          if (mounted) {
            setState(() {
              scoreData = rescored;
            });
          }
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Property details saved.')));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save property details.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSavingParcel = false;
        });
      }
    }
  }

  Future<DateTime?> pickLeadDate(DateTime? initialDate) {
    final today = todayDateOnly();

    return showDatePicker(
      context: context,
      initialDate: initialDate ?? today,
      firstDate: DateTime(today.year - 10),
      lastDate: DateTime(today.year + 10),
    );
  }

  Future<void> updateReminderData(LeadReminderData updatedReminderData) async {
    final previousReminderData = reminderData;

    setState(() {
      reminderData = updatedReminderData;
      isSavingReminder = true;
    });

    try {
      await widget.onUpdateLeadReminderData(
        widget.lead.id,
        updatedReminderData,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Revisit reminder saved.')));
    } catch (_) {
      if (!mounted) return;

      setState(() {
        reminderData = previousReminderData;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save revisit reminder.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSavingReminder = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation =
        widget.lead.latitude != null && widget.lead.longitude != null;
    final statusOptions = leadStatusOptions.contains(status)
        ? leadStatusOptions
        : [status, ...leadStatusOptions];
    final sourceOptions = leadSourceOptions.contains(source)
        ? leadSourceOptions
        : [source, ...leadSourceOptions];
    final offerData = currentOfferData();

    return Scaffold(
      appBar: AppBar(title: const Text('Lead Details')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.lead.address,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (missionAttributionLabel != null) ...[
                const SizedBox(height: 8),
                Text(
                  missionAttributionLabel!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5F6368),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Condition: ${widget.lead.condition}',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Last Purchase Info',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sale date: ${widget.lead.saleData.lastSaleDate.isEmpty ? 'Not set' : widget.lead.saleData.lastSaleDate}',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sale price: ${formatMoney(widget.lead.saleData.lastSalePrice)}',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Deed type: ${widget.lead.saleData.deedType.isEmpty ? 'Not set' : widget.lead.saleData.deedType}',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Document date: ${widget.lead.saleData.documentDate.isEmpty ? 'Not set' : widget.lead.saleData.documentDate}',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Reception no: ${widget.lead.saleData.receptionNo.isEmpty ? 'Not set' : widget.lead.saleData.receptionNo}',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ARV / MAO Calculator',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: arvController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'ARV',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: repairCostController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Repair Cost',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: assignmentFeeController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Assignment Fee',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'MAO: ${formatMoney(offerData.mao)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Formula: (${formatMoney(offerData.arv)} x 70%) - ${formatMoney(offerData.repairCost ?? 0)} - ${formatMoney(offerData.assignmentFee ?? 0)}',
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isSavingOffer ? null : saveOfferDetails,
                          child: Text(
                            isSavingOffer
                                ? 'Saving Offer Numbers...'
                                : 'Save Offer Numbers',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Revisit Reminder',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(reminderData.followUpStatus),
                        initialValue: reminderData.followUpStatus,
                        decoration: const InputDecoration(
                          labelText: 'Follow-up Status',
                          border: OutlineInputBorder(),
                        ),
                        items: followUpStatusOptions
                            .map(
                              (statusOption) => DropdownMenuItem(
                                value: statusOption,
                                child: Text(statusOption),
                              ),
                            )
                            .toList(),
                        onChanged: isSavingReminder
                            ? null
                            : (value) {
                                if (value == null) return;

                                updateReminderData(
                                  reminderData.copyWith(followUpStatus: value),
                                );
                              },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Last visited: ${displayDate(reminderData.lastVisitedDate)}',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSavingReminder
                                  ? null
                                  : () async {
                                      final pickedDate = await pickLeadDate(
                                        reminderData.lastVisitedDate,
                                      );

                                      if (pickedDate == null) return;

                                      updateReminderData(
                                        reminderData.copyWith(
                                          lastVisitedDate: pickedDate,
                                        ),
                                      );
                                    },
                              child: const Text('Pick Last Visit'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSavingReminder
                                  ? null
                                  : () {
                                      updateReminderData(
                                        reminderData.copyWith(
                                          lastVisitedDate: todayDateOnly(),
                                        ),
                                      );
                                    },
                              child: const Text('Visited Today'),
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: isSavingReminder
                            ? null
                            : () {
                                updateReminderData(
                                  reminderData.copyWith(
                                    clearLastVisitedDate: true,
                                  ),
                                );
                              },
                        child: const Text('Clear Last Visit'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Reminder date: ${displayDate(reminderData.reminderDate)}',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSavingReminder
                                  ? null
                                  : () async {
                                      final pickedDate = await pickLeadDate(
                                        reminderData.reminderDate,
                                      );

                                      if (pickedDate == null) return;

                                      updateReminderData(
                                        reminderData.copyWith(
                                          reminderDate: pickedDate,
                                          followUpStatus: 'Scheduled',
                                        ),
                                      );
                                    },
                              child: const Text('Pick Reminder'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSavingReminder
                                  ? null
                                  : () {
                                      updateReminderData(
                                        reminderData.copyWith(
                                          reminderDate: todayDateOnly(),
                                          followUpStatus: 'Needs Revisit',
                                        ),
                                      );
                                    },
                              child: const Text('Due Today'),
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: isSavingReminder
                            ? null
                            : () {
                                updateReminderData(
                                  reminderData.copyWith(
                                    clearReminderDate: true,
                                    followUpStatus: 'None',
                                  ),
                                );
                              },
                        child: const Text('Clear Reminder'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Parcel Property Details',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: ownerNameController,
                        decoration: const InputDecoration(
                          labelText: 'Owner Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: mailingAddressController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Mailing Address',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Out-of-state owner'),
                        value: outOfStateOwner,
                        onChanged: isSavingParcel
                            ? null
                            : (value) {
                                setState(() {
                                  outOfStateOwner = value;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: assessedValueController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Assessed Value',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: propertyTypeController,
                        decoration: const InputDecoration(
                          labelText: 'Property Type',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: lotSizeController,
                        decoration: const InputDecoration(
                          labelText: 'Lot Size',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: yearBuiltController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Year Built',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isSavingParcel ? null : saveParcelDetails,
                          child: Text(
                            isSavingParcel
                                ? 'Saving Property Details...'
                                : 'Save Property Details',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Lead Score',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: leadScoreColor(scoreData.score),
                              ),
                            ),
                          ),
                          leadScoreBadge(scoreData.score, fontSize: 18),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        scoreData.scoreOverride
                            ? 'Manual override'
                            : 'Auto score',
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Broken windows'),
                        value: scoreData.brokenWindows,
                        onChanged: isSavingScore
                            ? null
                            : (value) {
                                updateScoreData(
                                  scoreDataWithAutoScore(
                                    brokenWindows: value ?? false,
                                  ),
                                );
                              },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Roof damage'),
                        value: scoreData.roofDamage,
                        onChanged: isSavingScore
                            ? null
                            : (value) {
                                updateScoreData(
                                  scoreDataWithAutoScore(
                                    roofDamage: value ?? false,
                                  ),
                                );
                              },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Tall grass'),
                        value: scoreData.tallGrass,
                        onChanged: isSavingScore
                            ? null
                            : (value) {
                                updateScoreData(
                                  scoreDataWithAutoScore(
                                    tallGrass: value ?? false,
                                  ),
                                );
                              },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Trash in yard'),
                        value: scoreData.trashInYard,
                        onChanged: isSavingScore
                            ? null
                            : (value) {
                                updateScoreData(
                                  scoreDataWithAutoScore(
                                    trashInYard: value ?? false,
                                  ),
                                );
                              },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Vacant appearance'),
                        value: scoreData.vacantAppearance,
                        onChanged: isSavingScore
                            ? null
                            : (value) {
                                updateScoreData(
                                  scoreDataWithAutoScore(
                                    vacantAppearance: value ?? false,
                                  ),
                                );
                              },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Manual score override'),
                        value: scoreData.scoreOverride,
                        onChanged: isSavingScore
                            ? null
                            : (value) {
                                updateScoreData(
                                  scoreDataWithAutoScore(
                                    scoreOverride: value,
                                    score: value
                                        ? scoreData.score
                                        : recomputeAutoScore(scoreData),
                                  ),
                                );
                              },
                      ),
                      if (scoreData.scoreOverride)
                        Slider(
                          min: 0,
                          max: 100,
                          divisions: 100,
                          label: scoreData.score.toString(),
                          value: scoreData.score.toDouble(),
                          onChanged: isSavingScore
                              ? null
                              : (value) {
                                  setState(() {
                                    scoreData = scoreData.copyWith(
                                      score: value.round(),
                                    );
                                  });
                                },
                          onChangeEnd: isSavingScore
                              ? null
                              : (value) {
                                  updateScoreData(
                                    scoreData.copyWith(
                                      score: value.round(),
                                      scoreOverride: true,
                                    ),
                                  );
                                },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(status),
                initialValue: status,
                decoration: const InputDecoration(
                  labelText: 'Pipeline Stage',
                  border: OutlineInputBorder(),
                ),
                items: statusOptions
                    .map(
                      (statusOption) => DropdownMenuItem(
                        value: statusOption,
                        child: Text(statusOption),
                      ),
                    )
                    .toList(),
                onChanged: isSavingStatus ? null : updateStatus,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(source),
                initialValue: source,
                decoration: const InputDecoration(
                  labelText: 'Source',
                  border: OutlineInputBorder(),
                ),
                items: sourceOptions
                    .map(
                      (sourceOption) => DropdownMenuItem(
                        value: sourceOption,
                        child: Text(sourceOption),
                      ),
                    )
                    .toList(),
                onChanged: isSavingSource ? null : updateSource,
              ),
              const SizedBox(height: 16),
              Text(
                hasLocation
                    ? 'Location: ${widget.lead.latitude!.toStringAsFixed(5)}, ${widget.lead.longitude!.toStringAsFixed(5)}'
                    : 'Location: Not saved',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 24),
              const Text(
                'Notes',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                widget.lead.notes.isEmpty
                    ? 'No notes added.'
                    : widget.lead.notes,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Photos',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: isUploadingPhoto ? null : uploadLeadPhoto,
                    icon: const Icon(Icons.add_a_photo),
                    label: Text(
                      isUploadingPhoto ? 'Uploading...' : 'Add Photo',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isLoadingPhotos)
                const Center(child: CircularProgressIndicator())
              else if (photos.isEmpty)
                const Text('No photos added.', style: TextStyle(fontSize: 18))
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: photos.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (context, index) {
                    final photo = photos[index];

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        photo.url,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image),
                          );
                        },
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
