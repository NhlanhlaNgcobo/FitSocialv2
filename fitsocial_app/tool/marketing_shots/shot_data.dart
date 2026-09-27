// Sample data for the marketing shots. Fictional people, real places.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/progress_models.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_models.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_text_style.dart';
import 'package:fitsocial_app/shared/reactions/fit_reaction.dart';
import 'package:fitsocial_app/shared/widgets/bottom_nav.dart';

/// A run traced over real OpenStreetMap paths by osm_route.py.
List<RoutePoint> _route(String name) {
  final raw = jsonDecode(
          File('tool/marketing_shots/routes/$name.json').readAsStringSync())
      as List<dynamic>;
  return [
    for (final p in raw)
      RoutePoint(
        latitude: (p[0] as num).toDouble(),
        longitude: (p[1] as num).toDouble(),
      ),
  ];
}

/// uShaka up the promenade to Battery Beach and back, 11.8 km.
List<RoutePoint> durbanBeachfront() => _route('durban');

/// Mouille Point to Sea Point pavilion and back, 7.2 km.
List<RoutePoint> seaPointLoop() => _route('seapoint');

FitReactionSummary reactions(Map<FitReaction, int> counts) => FitReactionSummary(
      counts: counts,
      total: counts.values.fold(0, (a, b) => a + b),
    );

final homeFeedPosts = <FeedPost>[
  FeedPost(
    id: 'p-sipho-run',
    authorId: 'u-sipho',
    userName: 'Sipho Ndlovu',
    activity: 'Morning Run',
    caption: 'uShaka to Battery Beach and back before work. The promenade at '
        '5:30 is a different city.',
    metricLabels: const ['11.8 km', '1:04:54', '5:30 /km'],
    timestamp: '2h',
    likes: 48,
    comments: 12,
    backgroundColors: const [],
    likedBy: const [],
    reactions: reactions({
      FitReaction.fire: 21,
      FitReaction.strong: 14,
      FitReaction.respect: 9,
      FitReaction.love: 4,
    }),
    postType: PostType.run,
    routePoints: durbanBeachfront(),
    taggedUsers: const [
      TaggedUser(id: 'u-ayanda', displayName: 'Ayanda Zulu', handle: 'ayanda.runs'),
    ],
  ),
  FeedPost(
    id: 'p-thandi-legs',
    authorId: 'u-thandi',
    userName: 'Thandi Khumalo',
    activity: 'Leg Day',
    caption: 'New squat PB. 90 kg for 5, and I could have had one more.',
    metricLabels: const [],
    timestamp: '4h',
    likes: 63,
    comments: 18,
    backgroundColors: const [],
    likedBy: const [],
    reactions: reactions({
      FitReaction.strong: 30,
      FitReaction.champion: 17,
      FitReaction.fire: 16,
    }),
    postType: PostType.workout,
    workoutData: const {
      'title': 'Leg Day',
      'duration': '1h 05m',
      'calories': '480',
      'exercises': [
        {'name': 'Back Squat', 'sets': 5, 'reps': 5, 'weightKg': 90},
        {'name': 'Romanian Deadlift', 'sets': 4, 'reps': 8, 'weightKg': 70},
        {'name': 'Walking Lunges', 'sets': 3, 'reps': 12, 'weightKg': 16},
        {'name': 'Leg Press', 'sets': 3, 'reps': 10, 'weightKg': 160},
      ],
    },
  ),
  FeedPost(
    id: 'p-neo-sea-point',
    authorId: 'u-neo',
    userName: 'Neo Mahlangu',
    activity: 'Evening Run',
    caption: 'Sea Point loop into the sunset. Two Oceans training, week 6.',
    metricLabels: const ['7.2 km', '38:10', '5:18 /km'],
    timestamp: '6h',
    likes: 37,
    comments: 7,
    backgroundColors: const [],
    likedBy: const [],
    reactions: reactions({
      FitReaction.fire: 18,
      FitReaction.rocket: 11,
      FitReaction.love: 8,
    }),
    postType: PostType.run,
    routePoints: seaPointLoop(),
  ),
];

/// AppShell's layout without go_router: the page with the floating nav over
/// it, on [index].
Widget inShell(Widget page, {int index = 0}) {
  return Scaffold(
    extendBody: true,
    backgroundColor: Colors.transparent,
    body: page,
    bottomNavigationBar: FitSocialBottomNav(
      currentIndex: index,
      onTap: (_) {},
      hidden: false,
    ),
  );
}

/// This week so far: Monday to today, one session a day.
List<ActivitySession> thisWeekSessions() {
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  final kinds = [
    (ActivityKind.run, 'Morning Run', 11.8),
    (ActivityKind.workout, 'Leg Day', null),
    (ActivityKind.run, 'Easy Run', 6.1),
    (ActivityKind.workout, 'Push Day', null),
    (ActivityKind.run, 'Tempo Run', 8.0),
    (ActivityKind.walk, 'Long Walk', 7.5),
    (ActivityKind.run, 'Long Run', 18.0),
  ];
  return [
    for (var d = 0; d < now.weekday; d++)
      ActivitySession(
        id: 's-$d',
        kind: kinds[d].$1,
        title: kinds[d].$2,
        startedAt: monday.add(Duration(days: d, hours: 5, minutes: 40)),
        duration: const Duration(minutes: 52),
        calories: 520,
        distanceKm: kinds[d].$3,
      ),
  ];
}

PulseSegment textPulse(String id, String author, String text,
    {String gradient = 'ember', PulseFont font = PulseFont.strong, int hoursAgo = 2}) {
  final now = DateTime.now();
  return PulseSegment(
    id: id,
    authorId: 'u-${author.split(' ').first.toLowerCase()}',
    authorName: author,
    type: PulseMediaType.text,
    createdAt: now.subtract(Duration(hours: hoursAgo)),
    expiresAt: now.add(Duration(hours: 24 - hoursAgo)),
    text: text,
    textStyle: PulseTextStyle(font: font),
    gradientKey: gradient,
    viewCount: 34,
  );
}

final trayPulses = <PulseSegment>[
  textPulse('pl-1', 'Lerato Mokoena', 'Comrades in 8 weeks. No days off.', hoursAgo: 1),
  textPulse('pl-2', 'Sipho Ndlovu', '5:30 club. Who is in tomorrow?',
      gradient: 'midnight', hoursAgo: 3),
  textPulse('pl-3', 'Thandi Khumalo', '90 kg x 5', gradient: 'blood', hoursAgo: 4),
  textPulse('pl-4', 'Neo Mahlangu', 'Sea Point at sunset', gradient: 'ice', hoursAgo: 6),
  textPulse('pl-5', 'Ayanda Zulu', 'Rest day. Pap and chakalaka.',
      gradient: 'forest', hoursAgo: 8),
];

/// Everyone who appears in the shots.
const people = <String, UserSearchResult>{
  'u-sipho': UserSearchResult(
      id: 'u-sipho', displayName: 'Sipho Ndlovu', handle: 'sipho.runs',
      initials: 'SN', postsCount: 214, location: 'Durban'),
  'u-lerato': UserSearchResult(
      id: 'u-lerato', displayName: 'Lerato Mokoena', handle: 'lerato.m',
      initials: 'LM', postsCount: 388, location: 'Pietermaritzburg'),
  'u-thandi': UserSearchResult(
      id: 'u-thandi', displayName: 'Thandi Khumalo', handle: 'thandi.lifts',
      initials: 'TK', postsCount: 156, location: 'Johannesburg'),
  'u-neo': UserSearchResult(
      id: 'u-neo', displayName: 'Neo Mahlangu', handle: 'neo.m',
      initials: 'NM', postsCount: 97, location: 'Cape Town'),
  'u-ayanda': UserSearchResult(
      id: 'u-ayanda', displayName: 'Ayanda Zulu', handle: 'ayanda.runs',
      initials: 'AZ', postsCount: 121, location: 'Umhlanga'),
};

/// The thread under Sipho's beachfront run.
List<Comment> runComments() {
  final now = DateTime.now();
  Comment c(String id, String who, String text, int minsAgo, {String? parent}) =>
      Comment(
        id: id,
        authorId: 'u-${who.split(' ').first.toLowerCase()}',
        authorName: who,
        text: text,
        createdAt: now.subtract(Duration(minutes: minsAgo)),
        parentId: parent,
      );
  return [
    c('c1', 'Ayanda Zulu', 'That pace on the promenade! Saturday long run, same spot?', 96),
    c('c2', 'Sipho Ndlovu', '@ayanda.runs 5:30 sharp at uShaka. Bring Lerato.', 88, parent: 'c1'),
    c('c3', 'Lerato Mokoena', "I'll be there. 25 km, easy pace, I promise.", 80, parent: 'c1'),
    c('c4', 'Thandi Khumalo', 'Battery Beach at sunrise is the best view in Durban.', 64),
    c('c5', 'Neo Mahlangu', 'Cape Town is jealous. Sea Point loop tomorrow.', 41),
  ];
}

/// Thandi's last few sessions, offered as Repeat chips.
List<RecentWorkout> recentWorkouts() {
  final now = DateTime.now();
  return [
    RecentWorkout(
      title: 'Upper Body Power',
      durationMinutes: 55,
      calories: 410,
      loggedAt: now.subtract(const Duration(days: 2)),
      exercises: const [
        ExerciseEntry(name: 'Bench Press', sets: 4, reps: 8, weightKg: 60),
        ExerciseEntry(name: 'Pull-ups', sets: 4, reps: 10),
        ExerciseEntry(name: 'Overhead Press', sets: 3, reps: 10, weightKg: 35),
      ],
    ),
    RecentWorkout(
      title: 'Leg Day',
      durationMinutes: 65,
      calories: 480,
      loggedAt: now.subtract(const Duration(days: 5)),
      exercises: const [
        ExerciseEntry(name: 'Back Squat', sets: 5, reps: 5, weightKg: 87.5),
        ExerciseEntry(name: 'Romanian Deadlift', sets: 4, reps: 8, weightKg: 70),
        ExerciseEntry(name: 'Leg Press', sets: 3, reps: 10, weightKg: 160),
      ],
    ),
    RecentWorkout(
      title: 'Hill Sprints + Core',
      durationMinutes: 35,
      calories: 320,
      loggedAt: now.subtract(const Duration(days: 7)),
      exercises: const [],
    ),
  ];
}

/// Sipho's run history for the profile grid: the two traced routes, cut and
/// reversed into different outings.
List<FeedPost> siphoRuns() {
  final durban = durbanBeachfront();
  final sea = seaPointLoop();
  List<RoutePoint> cut(List<RoutePoint> r, double a, double b) =>
      r.sublist((r.length * a).round(), (r.length * b).round());
  final routes = [
    (durban, '11.8 km'),
    (cut(durban, 0, 0.55), '6.4 km'),
    (sea, '7.2 km'),
    (cut(durban, 0.2, 0.9), '8.3 km'),
    (durban.reversed.toList(), '11.8 km'),
    (cut(sea, 0, 0.6), '4.3 km'),
    (cut(durban, 0.35, 1), '7.7 km'),
    (cut(durban, 0, 0.8), '9.4 km'),
    (sea.reversed.toList(), '7.2 km'),
  ];
  return [
    for (final (i, (route, km)) in routes.indexed)
      FeedPost(
        id: 'sr-$i',
        authorId: 'u-sipho',
        userName: 'Sipho Ndlovu',
        activity: 'Run',
        caption: '',
        metricLabels: [km, '45:10', '5:30 /km'],
        timestamp: '${i + 1}d',
        likes: 20 + i,
        comments: 3,
        backgroundColors: const [],
        likedBy: const [],
        postType: PostType.run,
        routePoints: route,
      ),
  ];
}
