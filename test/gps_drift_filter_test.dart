import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:market_coverage/src/gps_drift_filter.dart';

void main() {
  group('shouldRecordGpsRoutePoint', () {
    final now = DateTime(2026, 7, 8, 12);
    const start = LatLng(36.2695, -95.8547);
    const tinyDrift = LatLng(36.26952, -95.8547);
    const realMove = LatLng(36.2697, -95.8547);

    test('rejects low-accuracy samples before they become route points', () {
      final decision = shouldRecordGpsRoutePoint(
        point: start,
        accuracyMeters: 60,
        speedMetersPerSecond: 4,
        recordedAt: now,
      );

      expect(decision.shouldRecord, isFalse);
      expect(decision.reason, 'low_accuracy');
    });

    test('does not record the first stationary sample', () {
      final decision = shouldRecordGpsRoutePoint(
        point: start,
        accuracyMeters: 8,
        speedMetersPerSecond: 0,
        recordedAt: now,
      );

      expect(decision.shouldRecord, isFalse);
      expect(decision.reason, 'waiting_for_movement');
    });

    test('rejects tiny idle drift after tracking has started', () {
      final decision = shouldRecordGpsRoutePoint(
        point: tinyDrift,
        accuracyMeters: 8,
        speedMetersPerSecond: 0,
        recordedAt: now.add(const Duration(seconds: 20)),
        lastRecordedPoint: start,
        lastRecordedAt: now,
      );

      expect(decision.shouldRecord, isFalse);
      expect(decision.reason, 'too_close');
    });

    test('records a moving first sample when GPS speed is clear', () {
      final decision = shouldRecordGpsRoutePoint(
        point: start,
        accuracyMeters: 8,
        speedMetersPerSecond: 3,
        recordedAt: now,
      );

      expect(decision.shouldRecord, isTrue);
      expect(decision.reason, 'moving_first_point');
    });

    test(
      'infers movement when speed is unavailable but displacement is real',
      () {
        final decision = shouldRecordGpsRoutePoint(
          point: realMove,
          accuracyMeters: 8,
          speedMetersPerSecond: -1,
          recordedAt: now.add(const Duration(seconds: 10)),
          lastSamplePoint: start,
          lastSampleAt: now,
        );

        expect(decision.shouldRecord, isTrue);
        expect(decision.reason, 'moving');
      },
    );

    test('does not record while the previous point is still persisting', () {
      final decision = shouldRecordGpsRoutePoint(
        point: realMove,
        accuracyMeters: 8,
        speedMetersPerSecond: 4,
        recordedAt: now.add(const Duration(seconds: 10)),
        lastRecordedPoint: start,
        lastRecordedAt: now,
        isPersisting: true,
      );

      expect(decision.shouldRecord, isFalse);
      expect(decision.reason, 'persisting_previous_point');
    });
  });
}
