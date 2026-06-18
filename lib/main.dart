import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/coverage.dart';
import 'src/formatting.dart';
import 'src/geo.dart';
import 'src/lead_export.dart';
import 'src/scoring.dart';

// Re-export the extracted modules so existing imports of
// `package:market_coverage/main.dart` (app code and tests) keep working.
export 'src/coverage.dart';
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

  runApp(const MarketCoverageApp());
}

final supabase = Supabase.instance.client;

const String leadPhotosBucket = 'lead-photos';
const String coverageCity = 'Owasso';
const String primaryTulsaParcelLayerUrl =
    'https://map11.incog.org/arcgis11wa/rest/services/Parcels_TulsaCo/FeatureServer/0/query';
const String fallbackTulsaParcelLayerUrl =
    'https://services3.arcgis.com/JfsWgLAOPxX7NGuG/arcgis/rest/services/Production_Map/FeatureServer/50/query';
const List<String> tulsaParcelLayerUrls = [
  primaryTulsaParcelLayerUrl,
  fallbackTulsaParcelLayerUrl,
];
const List<String> supportedCoverageCities = [
  'Owasso',
  'Tulsa',
  'Broken Arrow',
  'Bixby',
  'Jenks',
  'Sand Springs',
  'Collinsville',
  'Skiatook',
];
const int visibleParcelZoom = 17;
const int houseNumberLabelZoom = 18;
const int visibleParcelLimit = 250;
const int visibleStreetLimit = 800;
const int missionStreetCount = 12;
const double streetCoverageMatchMiles = 0.035;
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
  final String? driveSessionId;
  final DateTime? createdAt;
  final DateTime? startedAt;
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
    required this.driveSessionId,
    required this.createdAt,
    required this.startedAt,
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
      driveSessionId: map['drive_session_id']?.toString(),
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString()),
      startedAt: map['started_at'] == null
          ? null
          : DateTime.tryParse(map['started_at'].toString()),
      completedAt: map['completed_at'] == null
          ? null
          : DateTime.tryParse(map['completed_at'].toString()),
    );
  }

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
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

  @override
  void initState() {
    super.initState();

    // Load account-scoped data only when there's a signed-in user; (re)load on
    // sign-in and clear on sign-out.
    isLoading = supabase.auth.currentSession != null;
    if (supabase.auth.currentSession != null) {
      bootstrapAccountAndLoad();
    }

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

    setState(() {
      leads = data.map<Lead>((item) => Lead.fromMap(item)).toList();
      leads.sort((a, b) => b.score.compareTo(a.score));
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

    try {
      await supabase.from('leads').insert(row);
    } catch (_) {
      row.remove('mission_id');
      await supabase.from('leads').insert(row);
    }

    await loadLeads();
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

    try {
      await supabase.from('leads').insert(row);
    } catch (_) {
      row.remove('target_score');
      try {
        await supabase.from('leads').insert(row);
      } catch (_) {
        row.remove('mission_id');
        await supabase.from('leads').insert(row);
      }
    }

    await loadLeads();
  }

  Future<void> updateLeadStatus(String leadId, String status) async {
    final normalizedStatus = normalizeLeadStage(status);

    await supabase
        .from('leads')
        .update({'status': normalizedStatus})
        .eq('account_id', activeAccountId ?? '')
        .eq('id', leadId);

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
                  isSignUp ? 'Create your account' : 'Sign in to continue',
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
      ),
      LeadListScreen(
        leads: widget.leads,
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
      ),
      const _BusinessTab(),
    ];

    return Scaffold(
      body: IndexedStack(index: selectedTabIndex, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedTabIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => selectedTabIndex = index),
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
        ],
      ),
    );
  }
}

class _AreasTab extends StatelessWidget {
  final GlobalKey<_DrivingScreenState> driveScreenKey;
  final VoidCallback onOpenDrive;
  final VoidCallback onCreateNewArea;

  const _AreasTab({
    required this.driveScreenKey,
    required this.onOpenDrive,
    required this.onCreateNewArea,
  });

  @override
  Widget build(BuildContext context) {
    final driveState = driveScreenKey.currentState;
    final areas = driveState?.driveAreas ?? const <DriveArea>[];
    final activeArea = driveState?.activeDriveArea;

    return Scaffold(
      appBar: AppBar(title: const Text('Areas')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Create New Area'),
              onPressed: onCreateNewArea,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.history),
              label: const Text('View Mission History'),
              onPressed: () {
                onOpenDrive();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Mission history is in the Drive controls.'),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'Drive Areas',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (driveState == null || driveState.isLoadingDriveAreas)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Loading saved drive areas...'),
                ),
              )
            else if (areas.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No saved drive areas yet.'),
                ),
              )
            else
              ...areas.map((area) {
                final isActive = activeArea?.id == area.id;
                final streets = driveState.streetsInsideArea(area);
                final covered = streets
                    .where(
                      (street) =>
                          driveState.coveredStreetIds.contains(street.id),
                    )
                    .length;
                final coverage = streets.isEmpty
                    ? 0.0
                    : (covered / streets.length) * 100;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(
                      isActive ? Icons.flag : Icons.map_outlined,
                      color: isActive
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF6B7280),
                    ),
                    title: Text(area.name),
                    subtitle: Text(
                      '${area.city} | ${coverage.toStringAsFixed(0)}% covered | ${area.status}',
                    ),
                    trailing: isActive
                        ? const Chip(label: Text('Active'))
                        : const Icon(Icons.chevron_right),
                    onTap: () async {
                      await driveState.setActiveDriveArea(area);
                      onOpenDrive();
                    },
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
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
  });

  @override
  State<DrivingScreen> createState() => _DrivingScreenState();
}

class _DrivingScreenState extends State<DrivingScreen> {
  final MapController mapController = MapController();
  final GlobalKey mapWorkspaceKey = GlobalKey();

  LatLng currentMapCenter = const LatLng(36.2695, -95.8547);
  double currentZoom = 13;
  String selectedCoverageCity = coverageCity;
  LatLng? myLocation;
  bool isFindingLocation = false;
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
  List<DriveArea> driveAreas = [];
  DriveArea? activeDriveArea;
  List<LatLng> drawingAreaPoints = [];
  bool isDrawAreaMode = false;
  bool isLoadingDriveAreas = true;
  bool isSavingDriveArea = false;
  bool showOnlyActiveArea = false;
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
  Mission? activeMission;
  List<Mission> completedMissions = [];
  Map<String, List<Lead>> missionLeadsById = {};
  bool isLoadingMissions = false;
  bool isSavingMission = false;

  // Lead map filters (display-only; does not affect data or other layers).
  bool showLeadsOnMap = true;
  Set<String> selectedLeadStages = {...leadStatusOptions};
  bool useMinLeadScore = false;
  double minLeadScore = 0;

  @override
  void initState() {
    super.initState();
    drivingLeads = widget.leads;
    loadSavedDrivingPoints();
    loadStreetCoverage();
    loadDriveAreas();
  }

  @override
  void didUpdateWidget(covariant DrivingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.leads != widget.leads) {
      drivingLeads = widget.leads;
    }
  }

  @override
  void dispose() {
    visibleParcelLoadTimer?.cancel();
    visibleStreetLoadTimer?.cancel();
    positionStream?.cancel();
    super.dispose();
  }

  Future<void> loadDrivingLeads() async {
    try {
      final data = await supabase
          .from('leads')
          .select()
          .eq('account_id', widget.activeAccountId)
          .order('created_at', ascending: false);
      final leads = data.map<Lead>((item) => Lead.fromMap(item)).toList();

      leads.sort((a, b) => b.score.compareTo(a.score));

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
      await loadMarketProperties();
      await loadMissions();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update active drive area.')),
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
        missionLeadsById = {};
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

      if (!mounted) return;

      setState(() {
        activeMission = openMission;
        completedMissions = missions
            .where((mission) => mission.status == 'completed')
            .toList(growable: false);
        isLoadingMissions = false;
      });

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

  String? missionIdForPoint(LatLng? point) {
    final mission = activeMission;
    final areaPolygon = activeDriveArea?.polygon ?? const <LatLng>[];

    if (mission == null || !mission.isActive) return null;
    if (point == null || areaPolygon.length < 3) return null;
    if (!pointInRing(point, areaPolygon)) return null;

    return mission.id;
  }

  Future<void> generateMission(
    List<StreetOpportunity> streetOpportunities,
  ) async {
    final area = activeDriveArea;
    if (area == null || isSavingMission) return;

    final existingOpen = activeMission;
    if (existingOpen != null && existingOpen.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This area already has an open mission.')),
      );
      return;
    }

    final missionStreets = streetOpportunities
        .where((opportunity) => !opportunity.isCovered && opportunity.score > 0)
        .take(missionStreetCount)
        .toList(growable: false);

    if (missionStreets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No uncovered opportunity streets found.'),
        ),
      );
      return;
    }

    setState(() {
      isSavingMission = true;
    });

    try {
      await supabase.from('missions').insert({
        'account_id': widget.activeAccountId,
        'created_by': supabase.auth.currentUser?.id,
        'drive_area_id': area.id,
        'status': 'active',
        'target_street_ids': missionStreets
            .map((opportunity) => opportunity.street.id)
            .toList(growable: false),
        'street_count': missionStreets.length,
        'opportunity_at_start': missionStreets.fold<double>(
          0,
          (total, opportunity) => total + opportunity.score,
        ),
      });

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
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isSavingMission = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not start mission.')));
    }
  }

  Future<void> startMissionDriving() async {
    final mission = activeMission;
    if (mission == null || isSavingMission) return;

    final sessionId = 'mission-${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      currentDriveSessionId = sessionId;
    });

    try {
      await supabase
          .from('missions')
          .update({
            'status': 'active',
            'started_at':
                mission.startedAt?.toUtc().toIso8601String() ??
                DateTime.now().toUtc().toIso8601String(),
            'drive_session_id': sessionId,
          })
          .eq('account_id', widget.activeAccountId)
          .eq('id', mission.id);

      await loadMissions();
      await startTracking(sessionIdOverride: sessionId);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start mission driving.')),
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
  }) async {
    final mission = activeMission;
    if (mission == null) return;

    try {
      if (isTracking) {
        await stopTracking();
      }

      await supabase
          .from('missions')
          .update({
            'status': 'completed',
            'completed_at': DateTime.now().toUtc().toIso8601String(),
            'leads_generated': leadsFound,
            'miles_driven': milesDriven,
            'streets_covered': streetsCovered,
            'opportunity_captured': opportunityCaptured,
          })
          .eq('account_id', widget.activeAccountId)
          .eq('id', mission.id);

      final attributedLeads = leadsForMission(mission);
      await loadMissions();

      if (!mounted) return;

      openMissionResults(
        mission: mission,
        areaName: activeDriveArea?.name ?? 'Drive Area',
        leads: attributedLeads,
        streetsCovered: streetsCovered,
        opportunityCaptured: opportunityCaptured,
        milesDriven: milesDriven,
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
        onUpdateLeadStatus: widget.onUpdateLeadStatus,
        onUpdateLeadSource: widget.onUpdateLeadSource,
        onUpdateLeadScoreData: widget.onUpdateLeadScoreData,
        onUpdateLeadParcelData: widget.onUpdateLeadParcelData,
        onUpdateLeadReminderData: widget.onUpdateLeadReminderData,
        onUpdateLeadOfferData: widget.onUpdateLeadOfferData,
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

      for (var offset = 0; ; offset += visibleParcelLimit) {
        final page = await fetchParcelsByLatLongBox(
          west: bounds.west,
          south: bounds.south,
          east: bounds.east,
          north: bounds.north,
          resultRecordCount: visibleParcelLimit,
          returnGeometry: true,
          resultOffset: offset,
        );

        for (final parcel in page) {
          final centroid = parcel.centroid;

          if (centroid == null || !pointInRing(centroid, area.polygon)) {
            continue;
          }

          parcelsByAccount[marketPropertyKey(parcel)] = parcel;
        }

        if (!mounted) return;

        setState(() {
          marketMapFetchedCount = parcelsByAccount.length;
          marketMapMessage =
              'Fetched $marketMapFetchedCount parcels inside the area...';
        });

        if (page.length < visibleParcelLimit) break;
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
        marketMapMessage = 'Market Map built: ${rows.length} parcels saved.';
      });

      focusMapWorkspace(
        mode: 'targets',
        point: polygonCenter(area.polygon),
        minZoom: 15,
        message: 'Targets map ready for ${area.name}.',
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isBuildingMarketMap = false;
        marketMapMessage = 'Could not build Market Map.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not build Market Map.')),
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
      selectedParcel = null;
      mapMode = 'drive';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tap the map to draw your area boundary.')),
    );
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
    final opportunities = streets.map((street) {
      final isCovered = coveredStreetIds.contains(street.id);
      var score = 0.0;

      if (!isCovered) {
        for (final property in properties) {
          final centroid = property.parcel.centroid;

          if (centroid == null) continue;

          if (distanceToStreetMiles(centroid, street) <=
              opportunityStreetMatchMiles) {
            score += property.targetScore;
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
    return mission.targetStreetIds
        .where((streetId) => coveredStreetIds.contains(streetId))
        .length;
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

  Future<String?> promptForDriveAreaName() {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Save drive area'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Area name'),
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, controller.text.trim());
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> saveDrawingArea() async {
    if (drawingAreaPoints.length < 3 || isSavingDriveArea) return;

    final name = await promptForDriveAreaName();
    if (name == null || name.isEmpty) return;

    setState(() {
      isSavingDriveArea = true;
    });

    try {
      await supabase
          .from('drive_areas')
          .update({'is_active': false})
          .eq('account_id', widget.activeAccountId)
          .eq('is_active', true);
      await supabase.from('drive_areas').insert({
        'account_id': widget.activeAccountId,
        'created_by': supabase.auth.currentUser?.id,
        'name': name,
        'city': selectedCoverageCity,
        'polygon': driveAreaPolygonToJson(drawingAreaPoints),
        'status': 'in_progress',
        'is_active': true,
      });

      if (!mounted) return;

      setState(() {
        isDrawAreaMode = false;
        drawingAreaPoints = [];
        isSavingDriveArea = false;
      });

      await loadDriveAreas();
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

  Future<void> changeCoverageCity(String city) async {
    setState(() {
      selectedCoverageCity = city;
      cityStreets = [];
      coveredStreetIds = {};
      totalCityStreetCount = 0;
    });

    await loadStreetCoverage();
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

    for (final point in points) {
      for (final street in cityStreets) {
        if (coveredStreetIds.contains(street.id) ||
            newlyCoveredStreets.containsKey(street.id)) {
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
      });
    }

    try {
      await saveStreetCoverage(newlyCoveredStreets, driveSessionId);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save street coverage.')),
      );
    }
  }

  Future<void> syncSavedDrivingPointsToStreetCoverage() async {
    if (isSyncingStreetCoverage ||
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
        });
      }

      await saveStreetCoverage(newlyCoveredStreets, null);
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
                                      await widget.onAddParcelLead(
                                        parcel,
                                        scoreData,
                                        missionIdForPoint(parcel.centroid),
                                      );

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
                                        const SnackBar(
                                          content: Text('Parcel lead added.'),
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
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      setState(() {
        locationMessage = 'Location services are turned off.';
      });
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      setState(() {
        locationMessage = 'Location permission denied.';
      });
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        locationMessage = 'Location permission permanently denied.';
      });
      return false;
    }

    return true;
  }

  Future<void> findMyLocation() async {
    setState(() {
      isFindingLocation = true;
      locationMessage = 'Finding your location...';
    });

    final allowed = await checkLocationPermission();

    if (!allowed) {
      setState(() {
        isFindingLocation = false;
      });
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
      ),
    );

    final newLocation = LatLng(position.latitude, position.longitude);

    setState(() {
      myLocation = newLocation;
      currentMapCenter = newLocation;
      isFindingLocation = false;
      locationMessage = 'Location found.';
    });

    mapController.move(newLocation, 16);
  }

  Future<void> startTracking({String? sessionIdOverride}) async {
    final allowed = await checkLocationPermission();

    if (!allowed) return;

    final sessionId =
        sessionIdOverride ?? 'drive-${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      isTracking = true;
      currentDriveSessionId = sessionId;
      locationMessage = 'Tracking started.';
      routePoints.clear();
    });

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );

    positionStream =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position position) async {
          final point = LatLng(position.latitude, position.longitude);

          setState(() {
            myLocation = point;
            routePoints.add(point);
            locationMessage = 'Tracking route... Points: ${routePoints.length}';
          });

          mapController.move(point, 17);

          await saveDrivingPoint(point, currentDriveSessionId);
          await markNearbyStreetsCovered(point, currentDriveSessionId);
        });
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

    final savedPointCount = routePoints.length;

    await loadSavedDrivingPoints();

    setState(() {
      isTracking = false;
      currentDriveSessionId = null;
      routePoints.clear();
      locationMessage = 'Tracking stopped. Points saved: $savedPointCount';
    });
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
    final streetCoveragePercent = totalStreetCount == 0
        ? 0.0
        : (coveredStreetCount / totalStreetCount) * 100;
    final isStreetCoverageLoading =
        isLoadingCoverage || isLoadingStreetCoverage;
    final hasStreetReferenceData = totalStreetCount > 0;
    final coverageHeadline = isStreetCoverageLoading
        ? 'Coverage: Loading...'
        : hasStreetReferenceData
        ? 'Coverage: ${streetCoveragePercent.toStringAsFixed(0)}%'
        : 'Coverage: Not available';
    final remainingStreetMiles = remainingMiles(
      coverageSegments,
      coveredStreetIds,
    );
    final coveredStreets = cityStreets
        .where((street) => coveredStreetIds.contains(street.id))
        .toList();
    final uncoveredStreets = cityStreets
        .where((street) => !coveredStreetIds.contains(street.id))
        .toList();
    final activeAreaPolygon = activeDriveArea?.polygon ?? const <LatLng>[];
    final activeAreaStreets = activeAreaPolygon.length < 3
        ? <CityStreet>[]
        : cityStreets
              .where(
                (street) => streetFallsInsidePolygon(street, activeAreaPolygon),
              )
              .toList();
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
    final streetOpportunities = streetOpportunitiesFor(
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
    final coveredMissionOpportunities = missionOpportunities
        .where(
          (opportunity) => coveredStreetIds.contains(opportunity.street.id),
        )
        .toList(growable: false);
    final uncoveredMissionOpportunities = missionOpportunities
        .where(
          (opportunity) => !coveredStreetIds.contains(opportunity.street.id),
        )
        .toList(growable: false);
    final missionCoveredCount = coveredMissionOpportunities.length;
    final missionStreetTotal = activeMission?.streetCount ?? 0;
    final missionOpportunityRemaining = uncoveredMissionOpportunities
        .fold<double>(0, (total, opportunity) => total + opportunity.score);
    final missionOpportunityCaptured =
        (activeMission?.opportunityAtStart ?? 0) - missionOpportunityRemaining;
    final nextMissionStreet = chooseNextMissionStreet(
      uncoveredMissionOpportunities,
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

    final missionPercent = missionStreetTotal == 0
        ? 0.0
        : (missionCoveredCount / missionStreetTotal) * 100;
    final nextStreetName = nextMissionStreet?.street.streetName.isEmpty ?? true
        ? 'Unnamed street'
        : nextMissionStreet!.street.streetName;

    return Scaffold(
      body: Stack(
        children: [
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
                              icon: const Icon(Icons.my_location),
                              onPressed: isFindingLocation
                                  ? null
                                  : findMyLocation,
                              label: Text(
                                isFindingLocation ? 'Finding...' : 'Find Me',
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
                                isTracking ? 'Stop Tracking' : 'Start Tracking',
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
                                isDrawAreaMode ? 'Exit Draw Area' : 'Draw Area',
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              loadVisibleParcels();
                              loadVisibleCityStreets();
                            },
                            onPositionChanged: (camera, _) {
                              final wasShowingHouseNumbers =
                                  currentZoom >= houseNumberLabelZoom;
                              final isShowingHouseNumbers =
                                  camera.zoom >= houseNumberLabelZoom;

                              if (wasShowingHouseNumbers !=
                                  isShowingHouseNumbers) {
                                setState(() {
                                  currentMapCenter = camera.center;
                                  currentZoom = camera.zoom;
                                });
                              } else {
                                currentMapCenter = camera.center;
                                currentZoom = camera.zoom;
                              }

                              scheduleVisibleParcelLoad();
                              scheduleVisibleStreetLoad();
                            },
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
                            if (activeAreaPolygon.length >= 3)
                              PolygonLayer(
                                polygons: [
                                  Polygon(
                                    points: activeAreaPolygon,
                                    color: const Color(0x1A1976D2),
                                    borderColor: const Color(0xFF0D47A1),
                                    borderStrokeWidth: 4,
                                  ),
                                ],
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
                            if (mapParcels.isNotEmpty)
                              MarkerLayer(
                                markers: mapParcels
                                    .where((parcel) => parcel.centroid != null)
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
                                  if (activeAreaStreets.isEmpty)
                                    const Text(
                                      'No street data for this area yet',
                                    )
                                  else ...[
                                    Text(
                                      'Area coverage: ${activeAreaCoveragePercent.toStringAsFixed(0)}% '
                                      '($activeAreaCoveredStreetCount/${activeAreaStreets.length} streets)',
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Covered streets: $activeAreaCoveredStreetCount',
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Remaining streets: $activeAreaRemainingStreetCount',
                                    ),
                                  ],
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
                                    title: const Text('Show only active area'),
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
                                            ? 'Building Market Map...'
                                            : 'Build Market Map',
                                      ),
                                      onPressed: isBuildingMarketMap
                                          ? null
                                          : buildMarketMap,
                                    ),
                                  ),
                                  if (marketMapMessage.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(marketMapMessage),
                                  ],
                                  if (topUncoveredOpportunities.isNotEmpty) ...[
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
                                          opportunity.street.streetName.isEmpty
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
                                                        topUncoveredOpportunities
                                                            .isEmpty
                                                    ? null
                                                    : () => generateMission(
                                                        streetOpportunities,
                                                      ),
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
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            LinearProgressIndicator(
                                              value: missionStreetTotal == 0
                                                  ? 0
                                                  : missionCoveredCount /
                                                        missionStreetTotal,
                                            ),
                                            const SizedBox(height: 12),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEEF2FF),
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
                                                      color: Color(0xFF4F46E5),
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
                                                    'Remaining opportunity: ${missionOpportunityRemaining.toStringAsFixed(0)} pts',
                                                    style: const TextStyle(
                                                      color: Color(0xFF4B5563),
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
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton.icon(
                                                    icon: const Icon(
                                                      Icons.pause,
                                                    ),
                                                    onPressed: pauseMission,
                                                    label: const Text('Pause'),
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
                                                      milesDriven: missionMiles,
                                                    ),
                                                    label: const Text('Finish'),
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
                                                      coveredStreetIds.contains(
                                                        opportunity.street.id,
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
                                                            opportunity.street,
                                                            message:
                                                                'Mission map focused on this street.',
                                                          ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ],
                                          ],
                                          if (completedMissions.isNotEmpty) ...[
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
                                                contentPadding: EdgeInsets.zero,
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
                                          () => targetFilterOutOfState = value,
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
                                      'Build the Market Map to ingest parcels for this area.',
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
                                                  ? property.parcel.ownerName ??
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
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      _DriveStatTile(
                                        label: 'Street coverage',
                                        value: hasStreetReferenceData
                                            ? '${streetCoveragePercent.toStringAsFixed(0)}%'
                                            : 'N/A',
                                        icon: Icons.timeline,
                                        color: const Color(0xFF2563EB),
                                      ),
                                      _DriveStatTile(
                                        label: 'Covered',
                                        value: coveredStreetCount.toString(),
                                        icon: Icons.check_circle,
                                        color: const Color(0xFF059669),
                                      ),
                                      _DriveStatTile(
                                        label: 'Remaining',
                                        value: remainingStreetCount.toString(),
                                        icon: Icons.route,
                                        color: const Color(0xFFF59E0B),
                                      ),
                                      _DriveStatTile(
                                        label: 'Miles left',
                                        value: remainingStreetMiles
                                            .toStringAsFixed(1),
                                        icon: Icons.social_distance,
                                        color: const Color(0xFFEA580C),
                                      ),
                                      _DriveStatTile(
                                        label: 'Total streets',
                                        value: totalStreetCount.toString(),
                                        icon: Icons.add_road,
                                        color: const Color(0xFF7C3AED),
                                      ),
                                      _DriveStatTile(
                                        label: 'Miles driven',
                                        value: totalMiles.toStringAsFixed(2),
                                        icon: Icons.speed,
                                        color: const Color(0xFF111827),
                                      ),
                                      _DriveStatTile(
                                        label: 'Leads',
                                        value: leadsFound.toString(),
                                        icon: Icons.person_pin_circle,
                                        color: const Color(0xFFDC2626),
                                      ),
                                    ],
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
                                    style: TextStyle(color: Color(0xFF6B7280)),
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
                                          : findMyLocation,
                                      label: Text(
                                        isFindingLocation
                                            ? 'Finding...'
                                            : 'Center On Me',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  DropdownButtonFormField<String>(
                                    initialValue: selectedCoverageCity,
                                    decoration: const InputDecoration(
                                      labelText: 'Coverage city',
                                    ),
                                    items: supportedCoverageCities
                                        .map(
                                          (city) => DropdownMenuItem(
                                            value: city,
                                            child: Text(city),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: isTracking
                                        ? null
                                        : (city) {
                                            if (city == null ||
                                                city == selectedCoverageCity) {
                                              return;
                                            }

                                            changeCoverageCity(city);
                                          },
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
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          activeMission == null
                              ? 'No Active Mission'
                              : activeDriveArea?.name ?? 'Active Mission',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Filter leads',
                        onPressed: openLeadFilterSheet,
                        icon: const Icon(Icons.filter_list),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Change map view',
                        icon: Icon(mapModeIcon(mapMode)),
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
                            child: Text('Mission'),
                          ),
                          PopupMenuItem(
                            value: 'targets',
                            child: Text('Targets'),
                          ),
                          PopupMenuItem(
                            value: 'coverage',
                            child: Text('Coverage'),
                          ),
                          PopupMenuItem(value: 'drive', child: Text('Drive')),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${missionPercent.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ],
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
              child: Container(
                height: 72,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.route, color: Color(0xFF2563EB)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        activeMission == null
                            ? 'No active mission - go to Areas to start one.'
                            : 'Next street: $nextStreetName',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Pan to next street',
                      onPressed: nextMissionStreet == null
                          ? null
                          : () => focusStreetWorkspace(
                              'mission',
                              nextMissionStreet.street,
                              message:
                                  'Mission map focused on your next street.',
                            ),
                      icon: const Icon(Icons.center_focus_strong),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 22,
            child: SafeArea(
              child: FloatingActionButton(
                backgroundColor: const Color(0xFFF97316),
                foregroundColor: Colors.white,
                tooltip: 'Quick Capture',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Quick Capture coming soon')),
                  );
                },
                child: const Icon(Icons.bolt),
              ),
            ),
          ),
        ],
      ),
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
    required this.onUpdateLeadStatus,
    required this.onUpdateLeadSource,
    required this.onUpdateLeadScoreData,
    required this.onUpdateLeadParcelData,
    required this.onUpdateLeadReminderData,
    required this.onUpdateLeadOfferData,
  });

  @override
  Widget build(BuildContext context) {
    final leadsPerMile = milesDriven == 0 ? 0.0 : leads.length / milesDriven;
    final completedAt = mission.completedAt?.toLocal();
    final opportunityPercent = mission.opportunityAtStart == 0
        ? 0.0
        : (opportunityCaptured / mission.opportunityAtStart) * 100;

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
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => LeadDetailsScreen(
                                        lead: lead,
                                        onUpdateLeadStatus: onUpdateLeadStatus,
                                        onUpdateLeadSource: onUpdateLeadSource,
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

    if (mounted) {
      Navigator.pop(context);
    }
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
  String searchQuery = '';
  String stageFilter = 'All';

  Future<void> exportLeadsCsv(List<Lead> leads) async {
    await Clipboard.setData(ClipboardData(text: leadsToCsv(leads)));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied ${leads.length} leads as CSV to the clipboard.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedLeads = [...widget.leads]
      ..sort((a, b) => b.score.compareTo(a.score));
    final stages = <String>{
      'All',
      ...sortedLeads.map((lead) => normalizeLeadStage(lead.status)),
    }.toList();
    final normalizedQuery = searchQuery.trim().toLowerCase();
    final filteredLeads = sortedLeads
        .where((lead) {
          final stage = normalizeLeadStage(lead.status);
          final matchesStage = stageFilter == 'All' || stage == stageFilter;
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
              lead.notes.toLowerCase().contains(normalizedQuery);

          return matchesStage && matchesSearch;
        })
        .toList(growable: false);
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
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search address, owner, or notes',
                    ),
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
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
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: filteredLeads.isEmpty
                  ? Card(
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
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
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
                    )
                  : ListView.separated(
                      itemCount: filteredLeads.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final lead = filteredLeads[index];

                        return _LeadListRow(
                          lead: lead,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LeadDetailsScreen(
                                  lead: lead,
                                  onUpdateLeadStatus: (leadId, status) async {
                                    await widget.onUpdateLeadStatus(
                                      leadId,
                                      status,
                                    );

                                    if (mounted) {
                                      setState(() {});
                                    }
                                  },
                                  onUpdateLeadSource: (leadId, source) async {
                                    await widget.onUpdateLeadSource(
                                      leadId,
                                      source,
                                    );

                                    if (mounted) {
                                      setState(() {});
                                    }
                                  },
                                  onUpdateLeadScoreData:
                                      (leadId, scoreData) async {
                                        await widget.onUpdateLeadScoreData(
                                          leadId,
                                          scoreData,
                                        );

                                        if (mounted) {
                                          setState(() {});
                                        }
                                      },
                                  onUpdateLeadParcelData:
                                      (leadId, parcelData) async {
                                        await widget.onUpdateLeadParcelData(
                                          leadId,
                                          parcelData,
                                        );

                                        if (mounted) {
                                          setState(() {});
                                        }
                                      },
                                  onUpdateLeadReminderData:
                                      (leadId, reminderData) async {
                                        await widget.onUpdateLeadReminderData(
                                          leadId,
                                          reminderData,
                                        );

                                        if (mounted) {
                                          setState(() {});
                                        }
                                      },
                                  onUpdateLeadOfferData:
                                      (leadId, offerData) async {
                                        await widget.onUpdateLeadOfferData(
                                          leadId,
                                          offerData,
                                        );

                                        if (mounted) {
                                          setState(() {});
                                        }
                                      },
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
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

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
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
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 3,
                child: Column(
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
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    leadStageBadge(stage),
                    _MiniInfoChip(
                      icon: Icons.sell,
                      label:
                          '$lastSaleDate ${formatMoney(lead.saleData.lastSalePrice)}',
                    ),
                    _MiniInfoChip(
                      icon: Icons.calculate,
                      label: 'MAO ${formatMoney(lead.mao)}',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
            ],
          ),
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
    return Container(
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
          Text(
            label,
            style: const TextStyle(color: Color(0xFF374151), fontSize: 12),
          ),
        ],
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

  Future<void> loadLeadPhotos() async {
    setState(() {
      isLoadingPhotos = true;
    });

    try {
      final files = await supabase.storage
          .from(leadPhotosBucket)
          .list(path: widget.lead.id);

      final loadedPhotos = files.where((file) => file.name.isNotEmpty).map((
        file,
      ) {
        final path = '${widget.lead.id}/${file.name}';

        return LeadPhoto(
          path: path,
          url: supabase.storage.from(leadPhotosBucket).getPublicUrl(path),
        );
      }).toList();

      if (!mounted) return;

      setState(() {
        photos = loadedPhotos;
        isLoadingPhotos = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoadingPhotos = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not load photos.')));
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
    final pickedPhoto = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (pickedPhoto == null) return;

    setState(() {
      isUploadingPhoto = true;
    });

    try {
      final photoBytes = await pickedPhoto.readAsBytes();
      final extension = photoExtension(pickedPhoto.name);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}$extension';
      final storagePath = '${widget.lead.id}/$fileName';

      await supabase.storage
          .from(leadPhotosBucket)
          .uploadBinary(
            storagePath,
            photoBytes,
            fileOptions: FileOptions(
              contentType: pickedPhoto.mimeType ?? photoContentType(fileName),
            ),
          );

      await loadLeadPhotos();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo uploaded.')));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not upload photo.')));
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
