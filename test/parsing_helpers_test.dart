import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:market_coverage/main.dart';

void main() {
  group('parseStreetPoint', () {
    test('parses latitude/longitude map fields', () {
      final point = parseStreetPoint({'lat': 36.1, 'lng': -95.9});

      expect(point, isNotNull);
      expect(point?.latitude, 36.1);
      expect(point?.longitude, -95.9);
    });

    test('parses latitude/longitude fallback map fields', () {
      final point = parseStreetPoint({'latitude': 36.1, 'longitude': -95.9});

      expect(point, isNotNull);
      expect(point?.latitude, 36.1);
      expect(point?.longitude, -95.9);
    });

    test('parses [lat, lng] list input', () {
      final point = parseStreetPoint([36.1, -95.9]);

      expect(point, isNotNull);
      expect(point?.latitude, 36.1);
      expect(point?.longitude, -95.9);
    });

    test('returns null for null input', () {
      expect(parseStreetPoint(null), isNull);
    });

    test('returns null when list is too short', () {
      expect(parseStreetPoint([36.1]), isNull);
    });
  });

  group('parseStreetPath', () {
    test('returns empty for non-list input', () {
      expect(parseStreetPath(null), isEmpty);
    });

    test('parses list of valid points', () {
      final points = parseStreetPath([
        [36.0, -95.0],
        [36.1, -95.1],
      ]);

      expect(points, hasLength(2));
      expect(points[0], const LatLng(36.0, -95.0));
      expect(points[1], const LatLng(36.1, -95.1));
    });

    test('filters out invalid points', () {
      final points = parseStreetPath([
        [36.0, -95.0],
        ['invalid', 'point'],
      ]);

      expect(points, hasLength(1));
    });
  });

  group('parseLatLngFromAttributes', () {
    test('parses Lat and Long attributes', () {
      final point = parseLatLngFromAttributes({'Lat': 36.2, 'Long': -95.8});

      expect(point, isNotNull);
      expect(point?.latitude, 36.2);
      expect(point?.longitude, -95.8);
    });

    test('returns null when longitude is missing', () {
      expect(parseLatLngFromAttributes({'Lat': 36.2}), isNull);
    });
  });

  group('polygonCentroid', () {
    test('returns average of first ring vertices', () {
      final centroid = polygonCentroid([
        [
          const LatLng(36.0, -95.0),
          const LatLng(36.0, -95.2),
          const LatLng(36.2, -95.2),
          const LatLng(36.2, -95.0),
        ],
      ]);

      expect(centroid, isNotNull);
      expect(centroid!.latitude, closeTo(36.1, 0.001));
      expect(centroid.longitude, closeTo(-95.1, 0.001));
    });

    test('returns null for empty rings', () {
      expect(polygonCentroid([]), isNull);
    });

    test('returns null for first ring empty', () {
      expect(polygonCentroid([[]]), isNull);
    });
  });

  group('formatDecimal', () {
    test('returns Not set for null', () {
      expect(formatDecimal(null), 'Not set');
    });

    test('formats whole numbers without decimals', () {
      expect(formatDecimal(5.0), '5');
    });

    test('formats fractional values with two decimals', () {
      expect(formatDecimal(5.25), '5.25');
    });
  });

  group('displayDate', () {
    test('returns Not set for null', () {
      expect(displayDate(null), 'Not set');
    });

    test('formats y-m-d date', () {
      expect(displayDate(DateTime(2024, 3, 5)), '2024-03-05');
    });
  });
}
