// Unit tests for the point-in-polygon parcel hit-testing geometry.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:market_coverage/main.dart';

void main() {
  // A simple square ring (lat 36.00–36.01, lng -95.01 to -95.00).
  final square = <LatLng>[
    const LatLng(36.00, -95.01),
    const LatLng(36.00, -95.00),
    const LatLng(36.01, -95.00),
    const LatLng(36.01, -95.01),
  ];

  group('pointInRing', () {
    test('point inside the polygon is true', () {
      expect(pointInRing(const LatLng(36.005, -95.005), square), isTrue);
    });

    test('point north of the polygon is false', () {
      expect(pointInRing(const LatLng(36.02, -95.005), square), isFalse);
    });

    test('point east of the polygon is false', () {
      expect(pointInRing(const LatLng(36.005, -94.50), square), isFalse);
    });

    test('degenerate ring (<3 points) is false', () {
      expect(
        pointInRing(const LatLng(36.005, -95.005), [
          const LatLng(36.0, -95.0),
          const LatLng(36.0, -94.0),
        ]),
        isFalse,
      );
    });
  });

  group('ringsContainPoint', () {
    final otherSquare = <LatLng>[
      const LatLng(40.00, -90.01),
      const LatLng(40.00, -90.00),
      const LatLng(40.01, -90.00),
      const LatLng(40.01, -90.01),
    ];

    test('true when the point is in any ring', () {
      expect(
        ringsContainPoint([otherSquare, square], const LatLng(36.005, -95.005)),
        isTrue,
      );
    });

    test('false when the point is in no ring', () {
      expect(
        ringsContainPoint([square, otherSquare], const LatLng(0, 0)),
        isFalse,
      );
    });

    test('empty ring list is false', () {
      expect(ringsContainPoint([], const LatLng(36.005, -95.005)), isFalse);
    });
  });
}
