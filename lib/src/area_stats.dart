import 'package:latlong2/latlong.dart';

import 'coverage.dart';
import 'geo.dart';

class AreaStatsStreet {
  final String id;
  final List<LatLng> path;

  const AreaStatsStreet({required this.id, required this.path});
}

class AreaStatsLead {
  final LatLng? point;
  final int score;

  const AreaStatsLead({required this.point, required this.score});
}

class AreaStats {
  final double coveragePercent;
  final int streetsCovered;
  final int streetsRemaining;
  final double milesRemaining;
  final int leadsInArea;
  final int hotLeads;
  final int targetCount;
  final double totalMiles;
  final double coveredMiles;

  const AreaStats({
    required this.coveragePercent,
    required this.streetsCovered,
    required this.streetsRemaining,
    required this.milesRemaining,
    required this.leadsInArea,
    required this.hotLeads,
    required this.targetCount,
    required this.totalMiles,
    required this.coveredMiles,
  });
}

AreaStats computeAreaStats({
  required List<LatLng> polygon,
  required Iterable<AreaStatsStreet> streets,
  required Set<String> coveredStreetIds,
  required Iterable<AreaStatsLead> leads,
  required int targetCount,
  int hotLeadScoreThreshold = 70,
}) {
  final streetList = streets.toList(growable: false);
  final segments = streetList
      .map((street) => CoverageSegment(id: street.id, path: street.path))
      .toList(growable: false);
  final totalStreetMiles = totalMiles(segments);
  final coveredStreetMiles = coveredMiles(segments, coveredStreetIds);
  var leadsInArea = 0;
  var hotLeads = 0;

  for (final lead in leads) {
    final point = lead.point;
    if (point == null || !pointInRing(point, polygon)) continue;

    leadsInArea++;
    if (lead.score >= hotLeadScoreThreshold) hotLeads++;
  }

  return AreaStats(
    coveragePercent: coveragePercentByMiles(segments, coveredStreetIds),
    streetsCovered: streetList
        .where((street) => coveredStreetIds.contains(street.id))
        .length,
    streetsRemaining: streetList
        .where((street) => !coveredStreetIds.contains(street.id))
        .length,
    milesRemaining: remainingMiles(segments, coveredStreetIds),
    leadsInArea: leadsInArea,
    hotLeads: hotLeads,
    targetCount: targetCount,
    totalMiles: totalStreetMiles,
    coveredMiles: coveredStreetMiles,
  );
}
