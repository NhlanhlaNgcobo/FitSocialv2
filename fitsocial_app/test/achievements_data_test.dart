import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';

AchievementsData dataWith({
  int streak = 0,
  int workouts = 0,
  int meals = 0,
  int runs = 0,
  double longestRunKm = 0,
}) {
  return AchievementsData(
    currentXp: 0,
    nextLevelXp: AchievementXp.perLevel,
    level: 1,
    currentStreak: streak,
    badges: const [],
    totalWorkouts: workouts,
    totalMeals: meals,
    totalRuns: runs,
    longestRunKm: longestRunKm,
  );
}

void main() {
  group('streakWeeks', () {
    // The dashboard hides the weeks pill below one full week, so the boundary
    // at 7 is what decides whether it appears at all.
    test('is zero until a full week is banked', () {
      expect(dataWith(streak: 0).streakWeeks, 0);
      expect(dataWith(streak: 6).streakWeeks, 0);
    });

    test('turns over on the seventh day', () {
      expect(dataWith(streak: 7).streakWeeks, 1);
      expect(dataWith(streak: 13).streakWeeks, 1);
      expect(dataWith(streak: 14).streakWeeks, 2);
    });

    test('does not round a part-week up', () {
      expect(dataWith(streak: 20).streakWeeks, 2);
    });
  });

  group('totalActivities', () {
    test('sums every kind of log', () {
      expect(dataWith(workouts: 4, meals: 9, runs: 2).totalActivities, 15);
    });

    test('is zero for a brand new account', () {
      expect(dataWith().totalActivities, 0);
    });
  });

  test('totals default to zero when not supplied', () {
    const data = AchievementsData(
      currentXp: 0,
      nextLevelXp: 1000,
      level: 1,
      currentStreak: 0,
      badges: [],
    );
    expect(data.totalWorkouts, 0);
    expect(data.totalMeals, 0);
    expect(data.totalRuns, 0);
    expect(data.longestRunKm, 0);
  });
}
