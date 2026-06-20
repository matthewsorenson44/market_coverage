import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:market_coverage/src/area_stats.dart';
import 'package:market_coverage/src/coverage.dart';

void main() {
  const polygon = [
    LatLng(36.0, -95.0),
    LatLng(36.0, -94.99),
    LatLng(36.01, -94.99),
    LatLng(36.01, -95.0),
  ];

  group('computeAreaStats', () {
    test('returns covered and remaining street counts', () {
      final stats = computeAreaStats(
        polygon: polygon,
        streets: const [
          AreaStatsStreet(
            id: 'covered',
            path: [LatLng(36.001, -94.999), LatLng(36.002, -94.999)],
          ),
          AreaStatsStreet(
            id: 'remaining',
            path: [LatLng(36.003, -94.999), LatLng(36.004, -94.999)],
          ),
        ],
        coveredStreetIds: {'covered'},
        leads: const [],
        targetCount: 4,
      );

      expect(stats.streetsCovered, 1);
      expect(stats.streetsRemaining, 1);
      expect(stats.targetCount, 4);
    });

    test('uses mileage-based coverage percentage', () {
      const coveredPath = [LatLng(36.0, -95.0), LatLng(36.0, -94.9)];
      const remainingPath = [LatLng(36.0, -94.99), LatLng(36.0, -94.989)];
      final expected = coveragePercentByMiles(
        const [
          CoverageSegment(id: 'short', path: coveredPath),
          CoverageSegment(id: 'long', path: remainingPath),
        ],
        {'short'},
      );

      final stats = computeAreaStats(
        polygon: polygon,
        streets: const [
          AreaStatsStreet(id: 'short', path: coveredPath),
          AreaStatsStreet(id: 'long', path: remainingPath),
        ],
        coveredStreetIds: {'short'},
        leads: const [],
        targetCount: 0,
      );

      expect(stats.coveragePercent, closeTo(expected, 0.001));
      expect(stats.coveragePercent, greaterThan(50));
    });

    test('counts leads inside polygon only', () {
      final stats = computeAreaStats(
        polygon: polygon,
        streets: const [],
        coveredStreetIds: const {},
        leads: const [
          AreaStatsLead(point: LatLng(36.005, -94.995), score: 30),
          AreaStatsLead(point: LatLng(36.02, -94.995), score: 30),
          AreaStatsLead(point: null, score: 30),
        ],
        targetCount: 0,
      );

      expect(stats.leadsInArea, 1);
    });

    test('counts hot leads at threshold', () {
      final stats = computeAreaStats(
        polygon: polygon,
        streets: const [],
        coveredStreetIds: const {},
        leads: const [
          AreaStatsLead(point: LatLng(36.005, -94.995), score: 69),
          AreaStatsLead(point: LatLng(36.006, -94.995), score: 70),
          AreaStatsLead(point: LatLng(36.007, -94.995), score: 88),
        ],
        targetCount: 0,
      );

      expect(stats.leadsInArea, 3);
      expect(stats.hotLeads, 2);
    });

    test('handles empty cases', () {
      final stats = computeAreaStats(
        polygon: const [],
        streets: const [],
        coveredStreetIds: const {},
        leads: const [],
        targetCount: 0,
      );

      expect(stats.coveragePercent, 0);
      expect(stats.streetsCovered, 0);
      expect(stats.streetsRemaining, 0);
      expect(stats.milesRemaining, 0);
      expect(stats.leadsInArea, 0);
      expect(stats.hotLeads, 0);
    });
  });
}
