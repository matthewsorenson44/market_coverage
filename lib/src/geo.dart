/// Pure geometry helpers operating on lat/lng coordinates (no model or Flutter
/// dependencies), so they're trivially unit-testable.
library;

import 'package:latlong2/latlong.dart';

/// Ray-casting point-in-polygon test for a single ring.
///
/// Treats longitude as x and latitude as y on a flat plane, which is accurate
/// at parcel scale. A point exactly on an edge may return either result; that's
/// fine for tap selection.
bool pointInRing(LatLng point, List<LatLng> ring) {
  if (ring.length < 3) return false;

  final x = point.longitude;
  final y = point.latitude;
  var inside = false;

  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i].longitude;
    final yi = ring[i].latitude;
    final xj = ring[j].longitude;
    final yj = ring[j].latitude;

    final intersects =
        ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi);

    if (intersects) inside = !inside;
  }

  return inside;
}

/// True when the point falls inside any of a parcel's rings.
bool ringsContainPoint(List<List<LatLng>> rings, LatLng point) {
  for (final ring in rings) {
    if (pointInRing(point, ring)) return true;
  }

  return false;
}
