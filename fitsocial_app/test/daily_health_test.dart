import 'package:fitsocial_app/features/challenges/domain/daily_health.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dailyHealthChanges', () {
    test('the first reading of a day writes everything it has', () {
      final changes = dailyHealthChanges(
        null,
        const DailyHealthReading(
          steps: 8000,
          manualSteps: 500,
          avgHeartRate: 71,
          maxHeartRate: 140,
          heartRateCoverageMinutes: 300,
          utcOffsetMinutes: 120,
        ),
      );
      expect(changes, {
        'steps': 8000,
        'manualSteps': 500,
        'avgHeartRate': 71,
        'maxHeartRate': 140,
        'heartRateCoverageMinutes': 300,
        'utcOffsetMinutes': 120,
      });
    });

    test('a lower step reading changes nothing', () {
      final changes = dailyHealthChanges(
        {'steps': 9000, 'utcOffsetMinutes': 120},
        const DailyHealthReading(steps: 4000, utcOffsetMinutes: 120),
      );
      expect(changes, isNull);
    });

    test('a higher step reading raises the total', () {
      final changes = dailyHealthChanges(
        {'steps': 9000},
        const DailyHealthReading(steps: 9500),
      );
      expect(changes, {'steps': 9500});
    });

    test('manual steps only go up, and never above the total', () {
      expect(
        dailyHealthChanges(
          {'steps': 9000, 'manualSteps': 800},
          const DailyHealthReading(steps: 9000, manualSteps: 200),
        ),
        isNull,
      );
      expect(
        dailyHealthChanges(
          {'steps': 1000},
          const DailyHealthReading(steps: 1000, manualSteps: 5000),
        ),
        {'steps': 1000, 'manualSteps': 1000},
      );
    });

    test('an unreadable manual count leaves the stored one alone', () {
      final changes = dailyHealthChanges(
        {'steps': 9000, 'manualSteps': 800},
        const DailyHealthReading(steps: 9100),
      );
      expect(changes, {'steps': 9100});
    });

    test('heart rate is replaced by a reading covering more of the day', () {
      final changes = dailyHealthChanges(
        {
          'steps': 5000,
          'avgHeartRate': 80,
          'maxHeartRate': 150,
          'heartRateCoverageMinutes': 120,
        },
        const DailyHealthReading(
          steps: 5000,
          avgHeartRate: 74,
          maxHeartRate: 150,
          heartRateCoverageMinutes: 400,
        ),
      );
      expect(changes, {
        'avgHeartRate': 74,
        'maxHeartRate': 150,
        'heartRateCoverageMinutes': 400,
        'steps': 5000,
      });
    });

    test('a reading covering less of the day does not replace heart rate', () {
      // The phone lost the watch for the afternoon: one reading, not a trace.
      final changes = dailyHealthChanges(
        {
          'steps': 5000,
          'avgHeartRate': 74,
          'maxHeartRate': 150,
          'heartRateCoverageMinutes': 400,
        },
        const DailyHealthReading(
          steps: 5000,
          avgHeartRate: 90,
          maxHeartRate: 90,
          heartRateCoverageMinutes: 0,
        ),
      );
      expect(changes, isNull);
    });

    test('the offset alone is not worth a write', () {
      final changes = dailyHealthChanges(
        {'steps': 5000, 'utcOffsetMinutes': 120},
        const DailyHealthReading(steps: 5000, utcOffsetMinutes: 60),
      );
      expect(changes, isNull);
    });

    test('every write carries the total the rules check manual steps against',
        () {
      final changes = dailyHealthChanges(
        {'steps': 5000, 'manualSteps': 100},
        const DailyHealthReading(steps: 5000, manualSteps: 300),
      );
      expect(changes, {'manualSteps': 300, 'steps': 5000});
    });
  });

  group('rankableSteps', () {
    test('is the total less the hand-typed steps', () {
      expect(rankableSteps({'steps': 9000, 'manualSteps': 1500}), 7500);
      expect(hasManualSteps({'steps': 9000, 'manualSteps': 1500}), isTrue);
    });

    test('a day written before manual steps existed ranks on its total', () {
      expect(rankableSteps({'steps': 9000}), 9000);
      expect(hasManualSteps({'steps': 9000}), isFalse);
    });

    test('never goes negative', () {
      expect(rankableSteps({'steps': 100, 'manualSteps': 500}), 0);
      expect(rankableSteps({}), 0);
    });
  });
}
