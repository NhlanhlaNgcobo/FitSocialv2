import 'workout_models.dart';

/// The movements every user starts with.
///
/// Bundled rather than stored in Firestore: it never changes between releases,
/// it has to work with no signal in a gym basement, and a read-only list costs
/// nothing to ship. Anything not here is a [CustomExercise].
///
/// Ids are slugs of the name and are written onto logged entries, so renaming a
/// row changes its id and orphans every workout that used it. Add rows; do not
/// edit the names of released ones.
class ExerciseLibrary {
  const ExerciseLibrary._();

  static List<LibraryExercise> get all => _all ??= _parse(_rows);
  static List<LibraryExercise>? _all;

  static const equipmentTypes = [
    'barbell',
    'dumbbell',
    'machine',
    'cable',
    'bodyweight',
    'kettlebell',
    'band',
    'cardio',
    'other',
  ];

  static const muscleGroups = [
    'chest',
    'back',
    'shoulders',
    'biceps',
    'triceps',
    'forearms',
    'quads',
    'hamstrings',
    'glutes',
    'calves',
    'core',
    'full body',
    'cardio',
  ];

  /// The library entry with this id, or null.
  static LibraryExercise? byId(String id) {
    for (final exercise in all) {
      if (exercise.id == id) return exercise;
    }
    return null;
  }

  /// Name-or-muscle-or-equipment search, case-insensitive. Every word in
  /// [query] must match somewhere, so "incline db" finds the incline dumbbell
  /// press. Names that start with the query rank first.
  static List<LibraryExercise> search(
    String query, {
    Iterable<LibraryExercise> extra = const [],
  }) {
    final pool = [...extra, ...all];
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return pool;

    final hits = pool.where((exercise) {
      final haystack =
          '${exercise.name} ${exercise.muscles.join(' ')} ${exercise.equipment}'
              .toLowerCase();
      return words.every(haystack.contains);
    }).toList();
    final first = words.first;
    hits.sort((a, b) {
      final aStarts = a.name.toLowerCase().startsWith(first) ? 0 : 1;
      final bStarts = b.name.toLowerCase().startsWith(first) ? 0 : 1;
      return aStarts != bStarts
          ? aStarts.compareTo(bStarts)
          : a.name.compareTo(b.name);
    });
    return hits;
  }

  /// "Bench Press (Barbell)" -> "bench-press-barbell".
  static String slug(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  static List<LibraryExercise> _parse(List<String> rows) {
    final seen = <String>{};
    final out = <LibraryExercise>[];
    for (final row in rows) {
      final parts = row.split('|');
      final name = parts[0];
      final id = slug(name);
      // A duplicate id would make two entries indistinguishable in history.
      if (!seen.add(id)) continue;
      out.add(LibraryExercise(
        id: id,
        name: name,
        muscles: parts[1].split(','),
        equipment: parts[2],
      ));
    }
    return List.unmodifiable(out);
  }

  // name | muscles (comma separated) | equipment
  static const _rows = <String>[
    // Chest
    'Bench Press (Barbell)|chest,triceps,shoulders|barbell',
    'Incline Bench Press (Barbell)|chest,shoulders,triceps|barbell',
    'Decline Bench Press (Barbell)|chest,triceps|barbell',
    'Close Grip Bench Press (Barbell)|triceps,chest|barbell',
    'Bench Press (Dumbbell)|chest,triceps,shoulders|dumbbell',
    'Incline Bench Press (Dumbbell)|chest,shoulders,triceps|dumbbell',
    'Decline Bench Press (Dumbbell)|chest,triceps|dumbbell',
    'Chest Fly (Dumbbell)|chest|dumbbell',
    'Incline Chest Fly (Dumbbell)|chest,shoulders|dumbbell',
    'Chest Press (Machine)|chest,triceps|machine',
    'Incline Chest Press (Machine)|chest,shoulders|machine',
    'Pec Deck (Machine)|chest|machine',
    'Cable Crossover|chest|cable',
    'Low Cable Fly|chest,shoulders|cable',
    'Push Up|chest,triceps,shoulders|bodyweight',
    'Incline Push Up|chest,triceps|bodyweight',
    'Decline Push Up|chest,shoulders|bodyweight',
    'Diamond Push Up|triceps,chest|bodyweight',
    'Chest Dip|chest,triceps|bodyweight',
    'Svend Press|chest|other',
    'Landmine Press|chest,shoulders|barbell',
    // Back
    'Deadlift (Barbell)|back,hamstrings,glutes|barbell',
    'Romanian Deadlift (Barbell)|hamstrings,glutes,back|barbell',
    'Sumo Deadlift (Barbell)|glutes,hamstrings,back|barbell',
    'Trap Bar Deadlift|quads,glutes,back|barbell',
    'Rack Pull|back,glutes|barbell',
    'Bent Over Row (Barbell)|back,biceps|barbell',
    'Pendlay Row (Barbell)|back,biceps|barbell',
    'Bent Over Row (Dumbbell)|back,biceps|dumbbell',
    'One Arm Row (Dumbbell)|back,biceps|dumbbell',
    'Chest Supported Row (Dumbbell)|back,biceps|dumbbell',
    'T-Bar Row|back,biceps|barbell',
    'Seated Cable Row|back,biceps|cable',
    'Seated Row (Machine)|back,biceps|machine',
    'Lat Pulldown (Cable)|back,biceps|cable',
    'Close Grip Lat Pulldown|back,biceps|cable',
    'Straight Arm Pulldown|back|cable',
    'Pull Up|back,biceps|bodyweight',
    'Chin Up|back,biceps|bodyweight',
    'Wide Grip Pull Up|back|bodyweight',
    'Assisted Pull Up (Machine)|back,biceps|machine',
    'Inverted Row|back,biceps|bodyweight',
    'Meadows Row|back|barbell',
    'Back Extension|back,glutes,hamstrings|bodyweight',
    'Good Morning (Barbell)|hamstrings,back,glutes|barbell',
    'Shrug (Barbell)|back,shoulders|barbell',
    'Shrug (Dumbbell)|back,shoulders|dumbbell',
    'Face Pull|shoulders,back|cable',
    // Shoulders
    'Overhead Press (Barbell)|shoulders,triceps|barbell',
    'Seated Overhead Press (Barbell)|shoulders,triceps|barbell',
    'Push Press|shoulders,triceps,quads|barbell',
    'Shoulder Press (Dumbbell)|shoulders,triceps|dumbbell',
    'Seated Shoulder Press (Dumbbell)|shoulders,triceps|dumbbell',
    'Arnold Press (Dumbbell)|shoulders,triceps|dumbbell',
    'Shoulder Press (Machine)|shoulders,triceps|machine',
    'Lateral Raise (Dumbbell)|shoulders|dumbbell',
    'Lateral Raise (Cable)|shoulders|cable',
    'Lateral Raise (Machine)|shoulders|machine',
    'Front Raise (Dumbbell)|shoulders|dumbbell',
    'Front Raise (Cable)|shoulders|cable',
    'Rear Delt Fly (Dumbbell)|shoulders,back|dumbbell',
    'Reverse Pec Deck (Machine)|shoulders,back|machine',
    'Upright Row (Barbell)|shoulders,back|barbell',
    'Upright Row (Cable)|shoulders,back|cable',
    'Pike Push Up|shoulders,triceps|bodyweight',
    'Handstand Push Up|shoulders,triceps|bodyweight',
    'Band Pull Apart|shoulders,back|band',
    // Biceps
    'Bicep Curl (Barbell)|biceps|barbell',
    'EZ Bar Curl|biceps|barbell',
    'Preacher Curl (EZ Bar)|biceps|barbell',
    'Bicep Curl (Dumbbell)|biceps|dumbbell',
    'Alternating Dumbbell Curl|biceps|dumbbell',
    'Hammer Curl (Dumbbell)|biceps,forearms|dumbbell',
    'Incline Curl (Dumbbell)|biceps|dumbbell',
    'Concentration Curl|biceps|dumbbell',
    'Spider Curl|biceps|dumbbell',
    'Preacher Curl (Machine)|biceps|machine',
    'Bicep Curl (Cable)|biceps|cable',
    'Hammer Curl (Cable)|biceps,forearms|cable',
    'Bayesian Curl (Cable)|biceps|cable',
    'Reverse Curl (Barbell)|forearms,biceps|barbell',
    'Wrist Curl (Barbell)|forearms|barbell',
    'Reverse Wrist Curl|forearms|barbell',
    'Farmer Carry|forearms,core|dumbbell',
    // Triceps
    'Triceps Pushdown (Cable)|triceps|cable',
    'Triceps Rope Pushdown|triceps|cable',
    'Reverse Grip Pushdown|triceps|cable',
    'Overhead Triceps Extension (Cable)|triceps|cable',
    'Overhead Triceps Extension (Dumbbell)|triceps|dumbbell',
    'Skullcrusher (Barbell)|triceps|barbell',
    'Skullcrusher (Dumbbell)|triceps|dumbbell',
    'Triceps Kickback (Dumbbell)|triceps|dumbbell',
    'Triceps Dip|triceps,chest|bodyweight',
    'Bench Dip|triceps|bodyweight',
    'Triceps Extension (Machine)|triceps|machine',
    'JM Press|triceps|barbell',
    // Quads
    'Squat (Barbell)|quads,glutes|barbell',
    'Front Squat (Barbell)|quads,core|barbell',
    'Box Squat (Barbell)|quads,glutes|barbell',
    'Zercher Squat|quads,glutes,core|barbell',
    'Safety Bar Squat|quads,glutes|barbell',
    'Goblet Squat|quads,glutes|dumbbell',
    'Bulgarian Split Squat (Dumbbell)|quads,glutes|dumbbell',
    'Split Squat (Dumbbell)|quads,glutes|dumbbell',
    'Walking Lunge (Dumbbell)|quads,glutes|dumbbell',
    'Lunge (Barbell)|quads,glutes|barbell',
    'Reverse Lunge (Dumbbell)|quads,glutes|dumbbell',
    'Step Up (Dumbbell)|quads,glutes|dumbbell',
    'Leg Press (Machine)|quads,glutes|machine',
    'Hack Squat (Machine)|quads,glutes|machine',
    'Smith Machine Squat|quads,glutes|machine',
    'Leg Extension (Machine)|quads|machine',
    'Sissy Squat|quads|bodyweight',
    'Bodyweight Squat|quads,glutes|bodyweight',
    'Jump Squat|quads,glutes|bodyweight',
    'Wall Sit|quads|bodyweight',
    'Pistol Squat|quads,glutes|bodyweight',
    // Hamstrings and glutes
    'Romanian Deadlift (Dumbbell)|hamstrings,glutes|dumbbell',
    'Stiff Leg Deadlift|hamstrings,back|barbell',
    'Single Leg Romanian Deadlift|hamstrings,glutes|dumbbell',
    'Lying Leg Curl (Machine)|hamstrings|machine',
    'Seated Leg Curl (Machine)|hamstrings|machine',
    'Standing Leg Curl (Machine)|hamstrings|machine',
    'Nordic Curl|hamstrings|bodyweight',
    'Glute Ham Raise|hamstrings,glutes|bodyweight',
    'Hip Thrust (Barbell)|glutes,hamstrings|barbell',
    'Hip Thrust (Machine)|glutes|machine',
    'Hip Thrust (Dumbbell)|glutes|dumbbell',
    'Glute Bridge|glutes,hamstrings|bodyweight',
    'Single Leg Glute Bridge|glutes|bodyweight',
    'Cable Pull Through|glutes,hamstrings|cable',
    'Glute Kickback (Cable)|glutes|cable',
    'Glute Kickback (Machine)|glutes|machine',
    'Hip Abduction (Machine)|glutes|machine',
    'Hip Adduction (Machine)|quads|machine',
    'Cable Hip Abduction|glutes|cable',
    'Kettlebell Swing|glutes,hamstrings,back|kettlebell',
    'Curtsy Lunge|glutes,quads|dumbbell',
    'Frog Pump|glutes|bodyweight',
    // Calves
    'Standing Calf Raise (Machine)|calves|machine',
    'Seated Calf Raise (Machine)|calves|machine',
    'Calf Raise (Dumbbell)|calves|dumbbell',
    'Calf Raise (Barbell)|calves|barbell',
    'Leg Press Calf Raise|calves|machine',
    'Single Leg Calf Raise|calves|bodyweight',
    'Donkey Calf Raise|calves|machine',
    'Tibialis Raise|calves|bodyweight',
    // Core
    'Plank|core|bodyweight',
    'Side Plank|core|bodyweight',
    'Crunch|core|bodyweight',
    'Cable Crunch|core|cable',
    'Sit Up|core|bodyweight',
    'Decline Sit Up|core|bodyweight',
    'Hanging Leg Raise|core|bodyweight',
    'Hanging Knee Raise|core|bodyweight',
    'Lying Leg Raise|core|bodyweight',
    'Toes To Bar|core|bodyweight',
    'Russian Twist|core|bodyweight',
    'Weighted Russian Twist|core|dumbbell',
    'Bicycle Crunch|core|bodyweight',
    'Ab Wheel Rollout|core|other',
    'Mountain Climber|core,cardio|bodyweight',
    'Dead Bug|core|bodyweight',
    'Bird Dog|core,back|bodyweight',
    'Hollow Hold|core|bodyweight',
    'V Up|core|bodyweight',
    'Woodchopper (Cable)|core|cable',
    'Pallof Press|core|cable',
    'Suitcase Carry|core,forearms|dumbbell',
    'Ab Crunch (Machine)|core|machine',
    'Torso Rotation (Machine)|core|machine',
    // Full body and olympic
    'Clean (Barbell)|full body|barbell',
    'Power Clean|full body|barbell',
    'Hang Clean|full body|barbell',
    'Clean and Jerk|full body|barbell',
    'Snatch (Barbell)|full body|barbell',
    'Power Snatch|full body|barbell',
    'Thruster (Barbell)|full body|barbell',
    'Thruster (Dumbbell)|full body|dumbbell',
    'Dumbbell Snatch|full body|dumbbell',
    'Turkish Get Up|full body,core|kettlebell',
    'Kettlebell Clean and Press|full body|kettlebell',
    'Kettlebell Goblet Squat|quads,glutes|kettlebell',
    'Burpee|full body,cardio|bodyweight',
    'Box Jump|quads,glutes|bodyweight',
    'Broad Jump|quads,glutes|bodyweight',
    'Medicine Ball Slam|full body,core|other',
    'Wall Ball|full body|other',
    'Battle Ropes|full body,cardio|other',
    'Sled Push|quads,glutes|other',
    'Sled Pull|hamstrings,back|other',
    'Bear Crawl|full body,core|bodyweight',
    'Muscle Up|back,triceps,chest|bodyweight',
    'Rope Climb|back,biceps|other',
    'Man Maker|full body|dumbbell',
    // Cardio
    'Running (Outdoor)|cardio|cardio',
    'Treadmill Run|cardio|cardio',
    'Treadmill Walk|cardio|cardio',
    'Incline Walk|cardio,glutes|cardio',
    'Cycling (Outdoor)|cardio,quads|cardio',
    'Stationary Bike|cardio,quads|cardio',
    'Assault Bike|cardio,full body|cardio',
    'Rowing Machine|cardio,back|cardio',
    'Elliptical|cardio|cardio',
    'Stair Climber|cardio,glutes|cardio',
    'Ski Erg|cardio,back|cardio',
    'Swimming|cardio,full body|cardio',
    'Jump Rope|cardio,calves|cardio',
    'Jumping Jacks|cardio|bodyweight',
    'High Knees|cardio|bodyweight',
    'Shadow Boxing|cardio|bodyweight',
    'Hiking|cardio,glutes|cardio',
    // Machines, bands and extras
    'Smith Machine Bench Press|chest,triceps|machine',
    'Smith Machine Overhead Press|shoulders,triceps|machine',
    'Smith Machine Row|back,biceps|machine',
    'Smith Machine Lunge|quads,glutes|machine',
    'Cable Row (Single Arm)|back,biceps|cable',
    'Lat Pullover (Dumbbell)|back,chest|dumbbell',
    'Lat Pullover (Cable)|back|cable',
    'Pulldown (Machine)|back,biceps|machine',
    'High Row (Machine)|back|machine',
    'Low Row (Machine)|back|machine',
    'Resistance Band Squat|quads,glutes|band',
    'Resistance Band Row|back,biceps|band',
    'Resistance Band Chest Press|chest,triceps|band',
    'Resistance Band Curl|biceps|band',
    'Resistance Band Pushdown|triceps|band',
    'Banded Glute Bridge|glutes|band',
    'Banded Lateral Walk|glutes|band',
    'Clamshell|glutes|band',
    'Fire Hydrant|glutes|bodyweight',
    'Neck Flexion|core|other',
    'Dumbbell Pullover|chest,back|dumbbell',
    'Zottman Curl|biceps,forearms|dumbbell',
    'Cable Curl (Rope)|biceps,forearms|cable',
    'Cuban Press|shoulders|dumbbell',
    'Y Raise|shoulders|dumbbell',
    'Landmine Row|back,biceps|barbell',
    'Landmine Squat|quads,glutes|barbell',
    'Kettlebell Press|shoulders,triceps|kettlebell',
    'Kettlebell Row|back,biceps|kettlebell',
    'Kettlebell Deadlift|hamstrings,glutes|kettlebell',
    'Bodyweight Lunge|quads,glutes|bodyweight',
    'Lateral Lunge|quads,glutes|bodyweight',
    'Pause Squat (Barbell)|quads,glutes|barbell',
    'Pause Bench Press (Barbell)|chest,triceps|barbell',
    'Floor Press (Barbell)|chest,triceps|barbell',
    'Floor Press (Dumbbell)|chest,triceps|dumbbell',
    'Deficit Deadlift|back,hamstrings,glutes|barbell',
    'Block Pull|back,glutes|barbell',
    'Hex Bar Shrug|back,shoulders|barbell',
  ];
}
