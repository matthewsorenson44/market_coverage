import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:market_coverage/src/coverage.dart';

void main() {
  group('polylineMiles', () {
    test('returns 0 for empty and single-point paths', () {
      expect(polylineMiles([]), 0);
      expect(polylineMiles([const LatLng(36.0, -95.0)]), 0);
    });

    test('matches Distance for a two-point path', () {
      const start = LatLng(36.0, -95.0);
      const end = LatLng(36.1, -95.1);
      final expected = const Distance().as(LengthUnit.Mile, start, end);

      expect(polylineMiles([start, end]), closeTo(expected, 0.000001));
    });

    test('sums each leg in a three-point path', () {
      const first = LatLng(36.0, -95.0);
      const second = LatLng(36.1, -95.1);
      const third = LatLng(36.2, -95.05);
      final expected =
          const Distance().as(LengthUnit.Mile, first, second) +
          const Distance().as(LengthUnit.Mile, second, third);

      expect(
        polylineMiles([first, second, third]),
        closeTo(expected, 0.000001),
      );
    });
  });

  group('totalMiles and coveredMiles', () {
    test('sums all segments and selects only covered segment ids', () {
      const first = CoverageSegment(
        id: 'first',
        path: [LatLng(36.0, -95.0), LatLng(36.1, -95.1)],
      );
      const second = CoverageSegment(
        id: 'second',
        path: [LatLng(36.2, -95.2), LatLng(36.3, -95.3)],
      );
      final segments = [first, second];

      expect(
        totalMiles(segments),
        closeTo(first.lengthMiles + second.lengthMiles, 0.000001),
      );
      expect(
        coveredMiles(segments, {'second'}),
        closeTo(second.lengthMiles, 0.000001),
      );
    });
  });

  group('coveragePercentByMiles', () {
    test('returns 50 for one covered segment out of two equal segments', () {
      const segmentPath = [LatLng(36.0, -95.0), LatLng(36.1, -95.1)];
      const segments = [
        CoverageSegment(id: 'covered', path: segmentPath),
        CoverageSegment(id: 'remaining', path: segmentPath),
      ];

      expect(coveragePercentByMiles(segments, {'covered'}), closeTo(50, 0.001));
    });

    test('returns 0 for empty segments', () {
      expect(coveragePercentByMiles([], {'covered'}), 0);
    });

    test('returns 0 when no segment ids are covered', () {
      const segments = [
        CoverageSegment(
          id: 'remaining',
          path: [LatLng(36.0, -95.0), LatLng(36.1, -95.1)],
        ),
      ];

      expect(coveragePercentByMiles(segments, {}), 0);
    });
  });

  group('remainingMiles', () {
    test('returns total miles minus covered miles', () {
      const covered = CoverageSegment(
        id: 'covered',
        path: [LatLng(36.0, -95.0), LatLng(36.1, -95.1)],
      );
      const remaining = CoverageSegment(
        id: 'remaining',
        path: [LatLng(36.2, -95.2), LatLng(36.3, -95.3)],
      );
      final segments = [covered, remaining];

      expect(
        remainingMiles(segments, {'covered'}),
        closeTo(totalMiles(segments) - covered.lengthMiles, 0.000001),
      );
    });
  });
}
