import 'package:latlong2/latlong.dart';

const double routePointMaxAccuracyMeters = 25;
const double routePointMinMovingSpeedMetersPerSecond = 0.9;
const double routePointMinDisplacementMeters = 12;
const Duration routePointMinInterval = Duration(seconds: 3);

class GpsRoutePointDecision {
  final bool shouldRecord;
  final String reason;
  final double displacementMeters;
  final double effectiveSpeedMetersPerSecond;

  const GpsRoutePointDecision({
    required this.shouldRecord,
    required this.reason,
    required this.displacementMeters,
    required this.effectiveSpeedMetersPerSecond,
  });
}

GpsRoutePointDecision shouldRecordGpsRoutePoint({
  required LatLng point,
  required double accuracyMeters,
  required double speedMetersPerSecond,
  required DateTime recordedAt,
  LatLng? lastRecordedPoint,
  DateTime? lastRecordedAt,
  LatLng? lastSamplePoint,
  DateTime? lastSampleAt,
  bool isPersisting = false,
  double maxAccuracyMeters = routePointMaxAccuracyMeters,
  double minMovingSpeedMetersPerSecond =
      routePointMinMovingSpeedMetersPerSecond,
  double minDisplacementMeters = routePointMinDisplacementMeters,
  Duration minInterval = routePointMinInterval,
}) {
  if (isPersisting) {
    return const GpsRoutePointDecision(
      shouldRecord: false,
      reason: 'persisting_previous_point',
      displacementMeters: 0,
      effectiveSpeedMetersPerSecond: 0,
    );
  }

  if (!accuracyMeters.isFinite || accuracyMeters > maxAccuracyMeters) {
    return const GpsRoutePointDecision(
      shouldRecord: false,
      reason: 'low_accuracy',
      displacementMeters: 0,
      effectiveSpeedMetersPerSecond: 0,
    );
  }

  final hasMovingSpeed =
      speedMetersPerSecond.isFinite &&
      speedMetersPerSecond >= minMovingSpeedMetersPerSecond;
  final referencePoint = lastRecordedPoint ?? lastSamplePoint;
  final referenceAt = lastRecordedAt ?? lastSampleAt;

  if (referencePoint == null || referenceAt == null) {
    return GpsRoutePointDecision(
      shouldRecord: hasMovingSpeed,
      reason: hasMovingSpeed ? 'moving_first_point' : 'waiting_for_movement',
      displacementMeters: 0,
      effectiveSpeedMetersPerSecond: hasMovingSpeed ? speedMetersPerSecond : 0,
    );
  }

  final elapsed = recordedAt.difference(referenceAt);
  if (elapsed.isNegative) {
    return const GpsRoutePointDecision(
      shouldRecord: false,
      reason: 'stale_sample',
      displacementMeters: 0,
      effectiveSpeedMetersPerSecond: 0,
    );
  }

  final displacementMeters = const Distance().as(
    LengthUnit.Meter,
    referencePoint,
    point,
  );
  final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
  final inferredSpeed = elapsedSeconds <= 0
      ? 0.0
      : displacementMeters / elapsedSeconds;
  final effectiveSpeed = hasMovingSpeed ? speedMetersPerSecond : inferredSpeed;

  if (elapsed < minInterval && displacementMeters < minDisplacementMeters) {
    return GpsRoutePointDecision(
      shouldRecord: false,
      reason: 'too_soon_and_too_close',
      displacementMeters: displacementMeters,
      effectiveSpeedMetersPerSecond: effectiveSpeed,
    );
  }

  if (displacementMeters < minDisplacementMeters) {
    return GpsRoutePointDecision(
      shouldRecord: false,
      reason: 'too_close',
      displacementMeters: displacementMeters,
      effectiveSpeedMetersPerSecond: effectiveSpeed,
    );
  }

  final moving =
      hasMovingSpeed || inferredSpeed >= minMovingSpeedMetersPerSecond;
  return GpsRoutePointDecision(
    shouldRecord: moving,
    reason: moving ? 'moving' : 'below_speed_threshold',
    displacementMeters: displacementMeters,
    effectiveSpeedMetersPerSecond: effectiveSpeed,
  );
}
