import 'package:latlong2/latlong.dart';

class CoverageSegment {
  final String id;
  final List<LatLng> path;

  const CoverageSegment({required this.id, required this.path});

  double get lengthMiles => polylineMiles(path);
}

double polylineMiles(List<LatLng> path) {
  if (path.length < 2) return 0;

  var miles = 0.0;

  for (var index = 1; index < path.length; index++) {
    miles += const Distance().as(LengthUnit.Mile, path[index - 1], path[index]);
  }

  return miles;
}

double totalMiles(Iterable<CoverageSegment> segments) {
  var miles = 0.0;

  for (final segment in segments) {
    miles += segment.lengthMiles;
  }

  return miles;
}

double coveredMiles(
  Iterable<CoverageSegment> segments,
  Set<String> coveredIds,
) {
  var miles = 0.0;

  for (final segment in segments) {
    if (coveredIds.contains(segment.id)) {
      miles += segment.lengthMiles;
    }
  }

  return miles;
}

double coveragePercentByMiles(
  Iterable<CoverageSegment> segments,
  Set<String> coveredIds,
) {
  final total = totalMiles(segments);

  if (total == 0) return 0;

  return (coveredMiles(segments, coveredIds) / total) * 100;
}

double remainingMiles(
  Iterable<CoverageSegment> segments,
  Set<String> coveredIds,
) {
  return totalMiles(segments) - coveredMiles(segments, coveredIds);
}
