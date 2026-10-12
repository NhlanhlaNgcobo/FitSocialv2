import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/workout_math.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';

const _kgPlates = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25];
const _lbPlates = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5];

void main() {
  group('estimatedOneRepMax', () {
    test('a single is itself', () {
      expect(estimatedOneRepMax(100, 1), 100);
    });

    test('Epley for several reps', () {
      expect(estimatedOneRepMax(100, 5), closeTo(116.67, 0.01));
      expect(estimatedOneRepMax(60, 10), closeTo(80, 0.001));
    });

    test('nothing lifted estimates nothing', () {
      expect(estimatedOneRepMax(0, 10), 0);
      expect(estimatedOneRepMax(100, 0), 0);
    });
  });

  group('PersonalBests', () {
    ExerciseEntry entry(String name, List<ExerciseSet> sets, {String? id}) =>
        ExerciseEntry.fromSets(name: name, exerciseId: id, setLog: sets);

    PersonalBests bestsOf(List<ExerciseSet> sets) => PersonalBests.fromHistory([
          [entry('Bench', sets, id: 'bench')],
        ]);

    test('the first time a movement is done flags nothing', () {
      final bests = PersonalBests();

      expect(bests.check('bench', const ExerciseSet(weightKg: 100, reps: 5)),
          isEmpty);
    });

    test('a heavier set is a weight record', () {
      final bests = bestsOf(const [ExerciseSet(weightKg: 100, reps: 5)]);

      final broken =
          bests.check('bench', const ExerciseSet(weightKg: 102.5, reps: 3));

      expect(broken, contains(PrKind.weight));
    });

    test('matching the best is not a record', () {
      final bests = bestsOf(const [ExerciseSet(weightKg: 100, reps: 5)]);

      expect(bests.check('bench', const ExerciseSet(weightKg: 100, reps: 5)),
          isEmpty);
    });

    test('more reps at the same load is a rep record', () {
      final bests = bestsOf(const [ExerciseSet(weightKg: 100, reps: 5)]);

      final broken =
          bests.check('bench', const ExerciseSet(weightKg: 100, reps: 6));

      expect(broken, contains(PrKind.reps));
      expect(broken, isNot(contains(PrKind.weight)));
    });

    test('8 reps at 60 kg is no record when 8 at 70 is on the books', () {
      final bests = bestsOf(const [ExerciseSet(weightKg: 70, reps: 8)]);

      expect(bests.check('bench', const ExerciseSet(weightKg: 60, reps: 8)),
          isEmpty);
      expect(
        bests.check('bench', const ExerciseSet(weightKg: 60, reps: 9)),
        contains(PrKind.reps),
      );
    });

    test('a lighter, longer set can break the estimated 1RM', () {
      // 100 x 5 -> 116.7; 90 x 8 -> 114: no. 90 x 10 -> 120: yes.
      final bests = bestsOf(const [ExerciseSet(weightKg: 100, reps: 5)]);

      expect(
        bests.check('bench', const ExerciseSet(weightKg: 90, reps: 8)),
        isNot(contains(PrKind.oneRepMax)),
      );
      expect(
        bests.check('bench', const ExerciseSet(weightKg: 90, reps: 10)),
        contains(PrKind.oneRepMax),
      );
    });

    test('sets past twelve reps never count towards a 1RM record', () {
      final bests = bestsOf(const [ExerciseSet(weightKg: 100, reps: 5)]);

      expect(
        bests.check('bench', const ExerciseSet(weightKg: 90, reps: 20)),
        isNot(contains(PrKind.oneRepMax)),
      );
    });

    test('warm-ups neither break records nor set them', () {
      final bests = bestsOf(const [
        ExerciseSet(weightKg: 100, reps: 5),
        ExerciseSet(weightKg: 200, reps: 5, type: SetType.warmup),
      ]);

      expect(
        bests.check(
            'bench', const ExerciseSet(weightKg: 150, reps: 5, type: SetType.warmup)),
        isEmpty,
      );
      expect(
        bests.check('bench', const ExerciseSet(weightKg: 110, reps: 5)),
        contains(PrKind.weight),
      );
    });

    test('a rounding error is not a record', () {
      final bests = bestsOf(const [ExerciseSet(weightKg: 61.2349, reps: 5)]);

      expect(
        bests.check('bench', const ExerciseSet(weightKg: 61.23490001, reps: 5)),
        isEmpty,
      );
    });

    test('a record set earlier in the session raises the bar', () {
      final bests = bestsOf(const [ExerciseSet(weightKg: 100, reps: 5)]);
      const first = ExerciseSet(weightKg: 105, reps: 5);

      expect(bests.check('bench', first), contains(PrKind.weight));
      bests.record('bench', first);
      expect(bests.check('bench', first), isEmpty);
    });

    test('an old "3 x 10 at 60" entry counts as three sets of it', () {
      final bests = PersonalBests.fromHistory([
        [
          const ExerciseEntry(
              name: ' Bench  Press', sets: 3, reps: 10, weightKg: 60),
        ],
      ]);
      const key = 'name:bench press';

      expect(bests.hasHistory(key), isTrue);
      expect(bests.check(key, const ExerciseSet(weightKg: 65, reps: 10)),
          contains(PrKind.weight));
    });

    test('free-text names meet regardless of case and spacing', () {
      expect(
        exerciseKey(const ExerciseEntry(name: ' BENCH  press ', sets: 1, reps: 1)),
        exerciseKey(const ExerciseEntry(name: 'bench press', sets: 1, reps: 1)),
      );
      expect(
        exerciseKey(const ExerciseEntry(
            name: 'anything', sets: 1, reps: 1, exerciseId: 'bench-press-barbell')),
        'bench-press-barbell',
      );
    });
  });

  group('warmupRamp', () {
    test('ramps 40, 60 and 80 percent, rounded to the increment', () {
      final ramp = warmupRamp(100, bar: 20, increment: 2.5);

      expect(ramp.map((s) => s.weight), [40, 60, 80]);
      expect(ramp.map((s) => s.reps), [8, 5, 3]);
    });

    test('rounds to the nearest increment', () {
      final ramp = warmupRamp(97.5, bar: 20, increment: 2.5);

      expect(ramp.map((s) => s.weight), [40, 57.5, 77.5]);
    });

    test('never goes below the empty bar', () {
      final ramp = warmupRamp(40, bar: 20, increment: 2.5);

      // 16 would be under the bar, so it becomes the bar; 24 -> 25; 32 -> 32.5.
      expect(ramp.map((s) => s.weight), [20, 25, 32.5]);
    });

    test('collapsed steps are dropped', () {
      final ramp = warmupRamp(25, bar: 20, increment: 2.5);

      // 10 -> 20 (bar), 15 -> 20 (dup), 20 -> 20 (dup).
      expect(ramp.map((s) => s.weight), [20]);
    });

    test('a target at or under the bar needs no warm-up', () {
      expect(warmupRamp(20, bar: 20, increment: 2.5), isEmpty);
      expect(warmupRamp(15, bar: 20, increment: 2.5), isEmpty);
    });
  });

  group('platesPerSide', () {
    test('100 kg on a 20 kg bar is a 25 and a 15 each side', () {
      final plates = platesPerSide(100, bar: 20, plates: _kgPlates);

      expect(plates.perSide, [25, 15]);
      expect(plates.loaded, 100);
      expect(plates.shortfall, 0);
    });

    test('the empty bar needs no plates', () {
      final plates = platesPerSide(20, bar: 20, plates: _kgPlates);

      expect(plates.perSide, isEmpty);
      expect(plates.belowBar, isFalse);
    });

    test('small plates add up without floating-point drift', () {
      // One side carries (63.75 - 20) / 2 = 21.875: a 20 and a 1.25 make 21.25,
      // and the last 0.625 has no plate.
      final plates = platesPerSide(63.75, bar: 20, plates: _kgPlates);

      expect(plates.perSide, [20, 1.25]);
      expect(plates.loaded, 62.5);
      expect(plates.shortfall, 1.25);
    });

    test('a target the plates cannot make reports the shortfall', () {
      // One side carries 20.5; the 0.5 is smaller than any plate.
      final plates = platesPerSide(61, bar: 20, plates: _kgPlates);

      expect(plates.perSide, [20]);
      expect(plates.loaded, 60);
      expect(plates.shortfall, 1);
    });

    test('pounds work the same with a 45 lb bar', () {
      final plates = platesPerSide(225, bar: 45, plates: _lbPlates);

      expect(plates.perSide, [45, 45]);
      expect(plates.loaded, 225);
    });

    test('lighter than the bar is flagged', () {
      final plates = platesPerSide(15, bar: 20, plates: _kgPlates);

      expect(plates.belowBar, isTrue);
      expect(plates.perSide, isEmpty);
    });
  });
}
