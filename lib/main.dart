import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
const double streetCoverageMatchMiles = 0.035;

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
  StreamSubscription<AuthState>? authSubscription;

  @override
  void initState() {
    super.initState();

    // Load data only when there's a signed-in user; (re)load on sign-in and
    // clear on sign-out.
    isLoading = supabase.auth.currentSession != null;
    if (supabase.auth.currentSession != null) {
      loadLeads();
    }

    authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.signedIn:
          loadLeads();
        case AuthChangeEvent.signedOut:
          if (mounted) {
            setState(() {
              leads = [];
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
    final data = await supabase
        .from('leads')
        .select()
        .order('created_at', ascending: false);

    setState(() {
      leads = data.map<Lead>((item) => Lead.fromMap(item)).toList();
      leads.sort((a, b) => b.score.compareTo(a.score));
      isLoading = false;
    });
  }

  Future<void> addLead(
    String address,
    String condition,
    String notes,
    String source,
    LeadScoreData scoreData,
    double? latitude,
    double? longitude,
  ) async {
    await supabase.from('leads').insert({
      'user_id': supabase.auth.currentUser?.id,
      'address': address,
      'condition': condition,
      'notes': notes,
      'status': 'New Lead',
      'source': source,
      ...scoreData.toMap(),
      'latitude': latitude,
      'longitude': longitude,
    });

    await loadLeads();
  }

  Future<void> addParcelLead(
    ParcelProperty parcel,
    LeadScoreData scoreData,
  ) async {
    final leadLocation = parcel.centroid;

    await supabase.from('leads').insert({
      'user_id': supabase.auth.currentUser?.id,
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
    });

    await loadLeads();
  }

  Future<void> updateLeadStatus(String leadId, String status) async {
    final normalizedStatus = normalizeLeadStage(status);

    await supabase
        .from('leads')
        .update({'status': normalizedStatus})
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
    await supabase.from('leads').update(scoreData.toMap()).eq('id', leadId);

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
    await supabase.from('leads').update(parcelData.toMap()).eq('id', leadId);

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
    await supabase.from('leads').update(reminderData.toMap()).eq('id', leadId);

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
    await supabase.from('leads').update(offerData.toMap()).eq('id', leadId);

    setState(() {
      final index = leads.indexWhere((lead) => lead.id == leadId);

      if (index != -1) {
        leads[index] = leads[index].copyWith(offerData: offerData);
      }
    });
  }

  Future<void> updateLeadSource(String leadId, String source) async {
    await supabase.from('leads').update({'source': source}).eq('id', leadId);

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
      home: AuthGate(
        signedInBuilder: (context) => DashboardScreen(
          leads: leads,
          isLoading: isLoading,
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

/// Walls the app behind authentication: shows [LoginScreen] when signed out,
/// otherwise the signed-in app. Rebuilds on every auth state change.
class AuthGate extends StatelessWidget {
  final WidgetBuilder signedInBuilder;

  const AuthGate({super.key, required this.signedInBuilder});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (supabase.auth.currentSession == null) {
          return const LoginScreen();
        }

        return signedInBuilder(context);
      },
    );
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

class DashboardScreen extends StatelessWidget {
  final List<Lead> leads;
  final bool isLoading;
  final Future<void> Function(
    String address,
    String condition,
    String notes,
    String source,
    LeadScoreData scoreData,
    double? latitude,
    double? longitude,
  )
  onAddLead;
  final Future<void> Function(ParcelProperty parcel, LeadScoreData scoreData)
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
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Coverage: 0%',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Leads: ${leads.length}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
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
                              'Revisit Dashboard',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Leads needing revisit today: $leadsNeedingRevisitToday',
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Overdue revisits: $overdueRevisits',
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'New leads this week: $newLeadsThisWeek',
                              style: const TextStyle(fontSize: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DrivingScreen(
                                leads: leads,
                                onAddLead: onAddLead,
                                onAddParcelLead: onAddParcelLead,
                                onUpdateLeadStatus: onUpdateLeadStatus,
                                onUpdateLeadSource: onUpdateLeadSource,
                                onUpdateLeadScoreData: onUpdateLeadScoreData,
                                onUpdateLeadParcelData: onUpdateLeadParcelData,
                                onUpdateLeadReminderData:
                                    onUpdateLeadReminderData,
                                onUpdateLeadOfferData: onUpdateLeadOfferData,
                              ),
                            ),
                          );
                        },
                        child: const Text(
                          'Start Driving',
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  AddLeadScreen(onAddLead: onAddLead),
                            ),
                          );
                        },
                        child: const Text(
                          'Add Lead Manually',
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LeadListScreen(
                                leads: leads,
                                onUpdateLeadStatus: onUpdateLeadStatus,
                                onUpdateLeadSource: onUpdateLeadSource,
                                onUpdateLeadScoreData: onUpdateLeadScoreData,
                                onUpdateLeadParcelData: onUpdateLeadParcelData,
                                onUpdateLeadReminderData:
                                    onUpdateLeadReminderData,
                                onUpdateLeadOfferData: onUpdateLeadOfferData,
                              ),
                            ),
                          );
                        },
                        child: const Text(
                          'View Leads',
                          style: TextStyle(fontSize: 20),
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

class DrivingScreen extends StatefulWidget {
  final List<Lead> leads;

  final Future<void> Function(
    String address,
    String condition,
    String notes,
    String source,
    LeadScoreData scoreData,
    double? latitude,
    double? longitude,
  )
  onAddLead;
  final Future<void> Function(ParcelProperty parcel, LeadScoreData scoreData)
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

  // Lead map filters (display-only; does not affect data or other layers).
  bool showLeadsOnMap = true;
  Set<String> selectedLeadStages = {...leadStatusOptions};
  bool useMinLeadScore = false;
  double minLeadScore = 0;

  @override
  void initState() {
    super.initState();
    loadSavedDrivingPoints();
    loadStreetCoverage();
    loadDriveAreas();
  }

  @override
  void dispose() {
    visibleParcelLoadTimer?.cancel();
    visibleStreetLoadTimer?.cancel();
    positionStream?.cancel();
    super.dispose();
  }

  Future<void> loadSavedDrivingPoints() async {
    setState(() {
      isLoadingCoverage = true;
    });

    try {
      final data = await supabase.from('driving_points').select();
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
          .eq('is_active', true);

      if (area != null) {
        await supabase
            .from('drive_areas')
            .update({
              'is_active': true,
              'status': 'in_progress',
              'completed_at': null,
            })
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
          .eq('id', area.id);

      await loadDriveAreas();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not mark drive area complete.')),
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

  Future<void> startAreaDrive() async {
    final area = activeDriveArea;
    if (area == null) return;

    final center = polygonCenter(area.polygon);
    if (center != null) {
      mapController.move(center, math.max(currentZoom, 15));
    }

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

    mapController.move(focusPoint, math.max(currentZoom, 17));

    setState(() {
      locationMessage = nearestStreet!.streetName.isEmpty
          ? 'Centered on the next uncovered street.'
          : 'Next uncovered street: ${nearestStreet.streetName}.';
    });
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
          .eq('is_active', true);
      await supabase.from('drive_areas').insert({
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
  }) {
    return fetchParcelsFromArcGis(
      const {},
      resultRecordCount: resultRecordCount,
      returnGeometry: returnGeometry,
      where:
          "PAR_TYPE IN ('PARCEL','CONDO') AND Lat >= ${south.toStringAsFixed(8)} AND Lat <= ${north.toStringAsFixed(8)} AND Long >= ${west.toStringAsFixed(8)} AND Long <= ${east.toStringAsFixed(8)}",
    );
  }

  Future<List<ParcelProperty>> fetchParcelsFromArcGis(
    Map<String, String> geometryParameters, {
    required int resultRecordCount,
    required bool returnGeometry,
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
      for (final lead in widget.leads) {
        if (normalizedAddressKey(lead.address) == parcelAddressKey) {
          return lead;
        }
      }
    }

    final centroid = parcel.centroid;

    if (centroid == null) return null;

    final distance = Distance();

    for (final lead in widget.leads) {
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
    for (final parcel in visibleParcels) {
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

  Future<void> startTracking() async {
    final allowed = await checkLocationPermission();

    if (!allowed) return;

    setState(() {
      isTracking = true;
      currentDriveSessionId = 'drive-${DateTime.now().millisecondsSinceEpoch}';
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
        'latitude': point.latitude,
        'longitude': point.longitude,
        'drive_session_id': driveSessionId,
      });
    } catch (_) {
      await supabase.from('driving_points').insert({
        'user_id': supabase.auth.currentUser?.id,
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddLeadScreen(
          onAddLead: widget.onAddLead,
          latitude: myLocation?.latitude,
          longitude: myLocation?.longitude,
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
    final leadsFound = widget.leads.length;
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
        : widget.leads.where((lead) {
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
    final mapLeads = widget.leads.where(leadPassesMapFilter).where((lead) {
      if (!limitMapToActiveArea || activeAreaPolygon.length < 3) return true;

      return pointInRing(
        LatLng(lead.latitude!, lead.longitude!),
        activeAreaPolygon,
      );
    }).toList();
    final drawingBoundaryPoints = drawingAreaPoints.length > 2
        ? [...drawingAreaPoints, drawingAreaPoints.first]
        : drawingAreaPoints;
    final showHouseNumberLabels = currentZoom >= houseNumberLabelZoom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driving Mode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter leads',
            onPressed: openLeadFilterSheet,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
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
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isFindingLocation ? null : findMyLocation,
                      child: Text(isFindingLocation ? 'Finding...' : 'Find Me'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isTracking ? stopTracking : startTracking,
                      child: Text(
                        isTracking ? 'Stop Tracking' : 'Start Tracking',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: isTracking ? null : simulateDrive,
                  child: const Text('Simulate Drive'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  icon: Icon(isDrawAreaMode ? Icons.edit_off : Icons.edit),
                  label: Text(isDrawAreaMode ? 'Exit Draw Area' : 'Draw Area'),
                  onPressed: () {
                    setState(() {
                      isDrawAreaMode = !isDrawAreaMode;
                      selectedParcel = null;
                    });
                  },
                ),
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
                              isSavingDriveArea ? 'Saving...' : 'Save area',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 350,
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

                      if (wasShowingHouseNumbers != isShowingHouseNumbers) {
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
                    if (mapUncoveredStreets.isNotEmpty)
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
                    if (mapCoveredStreets.isNotEmpty)
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
                    if (!limitMapToActiveArea &&
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
                    if (visibleParcels.any((parcel) => parcel.rings.isNotEmpty))
                      PolygonLayer(
                        polygons: visibleParcels
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
                    if (visibleParcels.isNotEmpty)
                      MarkerLayer(
                        markers: visibleParcels
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
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Drive Areas',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
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
                            ...driveAreas.map(
                              (area) => DropdownMenuItem<String>(
                                value: area.id,
                                child: Text(
                                  area.isComplete
                                      ? '${area.name} (complete)'
                                      : area.name,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (areaId) {
                            if (areaId == null) return;

                            final area = areaId.isEmpty
                                ? null
                                : driveAreas
                                      .where((item) => item.id == areaId)
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
                            const Text('No street data for this area yet')
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
                              label: const Text('Next uncovered street'),
                              onPressed: activeAreaUncoveredStreets.isEmpty
                                  ? null
                                  : () => focusNextUncoveredStreet(
                                      activeAreaUncoveredStreets,
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
              DropdownButtonFormField<String>(
                initialValue: selectedCoverageCity,
                decoration: const InputDecoration(
                  labelText: 'Coverage city',
                  border: OutlineInputBorder(),
                ),
                items: supportedCoverageCities
                    .map(
                      (city) =>
                          DropdownMenuItem(value: city, child: Text(city)),
                    )
                    .toList(),
                onChanged: isTracking
                    ? null
                    : (city) {
                        if (city == null || city == selectedCoverageCity) {
                          return;
                        }

                        changeCoverageCity(city);
                      },
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Coverage Statistics',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (isStreetCoverageLoading)
                        const Text(
                          'Loading saved coverage...',
                          style: TextStyle(fontSize: 18),
                        )
                      else if (!hasStreetReferenceData) ...[
                        Text(
                          'City: $selectedCoverageCity',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No street data loaded for $selectedCoverageCity yet.',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Import city street data to enable coverage tracking here.',
                          style: TextStyle(fontSize: 18),
                        ),
                      ] else ...[
                        Text(
                          'City: $selectedCoverageCity',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Street coverage: ${streetCoveragePercent.toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Miles remaining: ${remainingStreetMiles.toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Visible streets covered: $visibleCoveredStreetCount',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Total streets: $totalStreetCount',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Streets covered: $coveredStreetCount',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Remaining streets: $remainingStreetCount',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Total route points: $totalRoutePoints',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Total miles driven: ${totalMiles.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Leads found: $leadsFound',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Leads per mile: ${leadsPerMile.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: openAddLeadFromLocation,
                  child: const Text(
                    'Add Lead At My Location',
                    style: TextStyle(fontSize: 20),
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

class AddLeadScreen extends StatefulWidget {
  final Future<void> Function(
    String address,
    String condition,
    String notes,
    String source,
    LeadScoreData scoreData,
    double? latitude,
    double? longitude,
  )
  onAddLead;

  final double? latitude;
  final double? longitude;

  const AddLeadScreen({
    super.key,
    required this.onAddLead,
    this.latitude,
    this.longitude,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lead List'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Copy leads as CSV',
            onPressed: sortedLeads.isEmpty
                ? null
                : () => exportLeadsCsv(sortedLeads),
          ),
        ],
      ),
      body: sortedLeads.isEmpty
          ? const Center(
              child: Text(
                'No leads saved yet.',
                style: TextStyle(fontSize: 22),
              ),
            )
          : ListView.builder(
              itemCount: sortedLeads.length,
              itemBuilder: (context, index) {
                final lead = sortedLeads[index];

                return Card(
                  margin: const EdgeInsets.all(12),
                  child: ListTile(
                    title: Text(
                      lead.address,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${lead.condition} | Stage: ${normalizeLeadStage(lead.status)}\nScore: ${lead.score} | Last sale: ${lead.saleData.lastSaleDate.isEmpty ? 'Not set' : lead.saleData.lastSaleDate} ${formatMoney(lead.saleData.lastSalePrice)}\nARV: ${formatMoney(lead.offerData.arv)} | MAO: ${formatMoney(lead.mao)}',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        leadStageBadge(lead.status),
                        const SizedBox(width: 8),
                        leadScoreBadge(lead.score),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () {
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
                              await widget.onUpdateLeadScoreData(
                                leadId,
                                scoreData,
                              );

                              if (mounted) {
                                setState(() {});
                              }
                            },
                            onUpdateLeadParcelData: (leadId, parcelData) async {
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
                            onUpdateLeadOfferData: (leadId, offerData) async {
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
                  ),
                );
              },
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
