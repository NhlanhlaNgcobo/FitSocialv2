// Mock fixtures for seeding the local Firestore emulator. Field names match
// the FirestoreUserRecord / FirestorePostRecord / FirestoreProgressRecord
// shapes read by lib/features/main/data in the Flutter app.

const users = [
  {
    id: 'mock-user-naledi',
    displayName: 'Naledi Khumalo',
    handle: '@naledi.trains',
    bio: 'Marathon in training. Coffee-powered.',
    location: 'Cape Town, ZA',
    avatarUrl: null,
    followersCount: 1842,
    followingCount: 312,
    postsCount: 6,
    workoutsCount: 41,
    mealsCount: 58,
  },
  {
    id: 'mock-user-sipho',
    displayName: 'Sipho Dlamini',
    handle: '@sipho_lifts',
    bio: 'Strength coach. PR chaser.',
    location: 'Johannesburg, ZA',
    avatarUrl: null,
    followersCount: 3021,
    followingCount: 198,
    postsCount: 5,
    workoutsCount: 96,
    mealsCount: 34,
  },
  {
    id: 'mock-user-amara',
    displayName: 'Amara Okafor',
    handle: '@amara.runs',
    bio: 'Sub-20 5K or bust.',
    location: 'Lagos, NG',
    avatarUrl: null,
    followersCount: 982,
    followingCount: 410,
    postsCount: 4,
    workoutsCount: 28,
    mealsCount: 19,
  },
  {
    id: 'mock-user-liam',
    displayName: 'Liam Foster',
    handle: '@liam.hiit',
    bio: 'HIIT every day keeps the donuts away.',
    location: 'London, UK',
    avatarUrl: null,
    followersCount: 2210,
    followingCount: 275,
    postsCount: 3,
    workoutsCount: 63,
    mealsCount: 47,
  },
  {
    id: 'mock-user-priya',
    displayName: 'Priya Nair',
    handle: '@priya.yoga',
    bio: 'Yoga and mobility nerd.',
    location: 'Mumbai, IN',
    avatarUrl: null,
    followersCount: 1567,
    followingCount: 233,
    postsCount: 4,
    workoutsCount: 52,
    mealsCount: 61,
  },
  {
    id: 'mock-user-carlos',
    displayName: 'Carlos Mendes',
    handle: '@carlos.cycles',
    bio: 'Weekend century rides.',
    location: 'Lisbon, PT',
    avatarUrl: null,
    followersCount: 874,
    followingCount: 156,
    postsCount: 3,
    workoutsCount: 37,
    mealsCount: 22,
  },
  {
    id: 'mock-user-zanele',
    displayName: 'Zanele Mokoena',
    handle: '@zanele.fit',
    bio: 'Postpartum strength journey.',
    location: 'Durban, ZA',
    avatarUrl: null,
    followersCount: 643,
    followingCount: 289,
    postsCount: 3,
    workoutsCount: 19,
    mealsCount: 26,
  },
  {
    id: 'mock-user-jordan',
    displayName: 'Jordan Kim',
    handle: '@jordan.swims',
    bio: 'Open water swimmer.',
    location: 'Seoul, KR',
    avatarUrl: null,
    followersCount: 1298,
    followingCount: 201,
    postsCount: 2,
    workoutsCount: 44,
    mealsCount: 30,
  },
];

// authorId/authorName reference the users above. themeKey must be one of
// 'burn' | 'graphite' | 'sunset' (see FirestoreMapper._themeColors).
// hoursAgo drives both createdAt (for the orderBy query) and timestampLabel.
const postsByHoursAgo = [
  {
    authorId: 'mock-user-naledi', authorName: 'Naledi Khumalo', activity: 'Run',
    caption: 'Easy 10K to shake out yesterday’s intervals.', themeKey: 'sunset',
    metricLabels: ['10.04 km', '52:18', '5:12 /km'], likesCount: 134, commentsCount: 12, hoursAgo: 1,
  },
  {
    authorId: 'mock-user-sipho', authorName: 'Sipho Dlamini', activity: 'Strength',
    caption: 'New deadlift PR. Logged 3 exercises, felt strong all session.', themeKey: 'burn',
    metricLabels: ['62 min', '540 kcal', '3 moves'], likesCount: 289, commentsCount: 31, hoursAgo: 3,
  },
  {
    authorId: 'mock-user-priya', authorName: 'Priya Nair', activity: 'Meal',
    caption: 'Post-practice protein bowl. Quinoa, chickpeas, grilled paneer.', themeKey: 'graphite',
    metricLabels: ['520 kcal', '34g protein', '14g fat'], likesCount: 76, commentsCount: 5, hoursAgo: 4,
  },
  {
    authorId: 'mock-user-liam', authorName: 'Liam Foster', activity: 'HIIT',
    caption: '20 minute EMOM. Lungs are still recovering.', themeKey: 'burn',
    metricLabels: ['20 min', '310 kcal', '4 moves'], likesCount: 201, commentsCount: 18, hoursAgo: 6,
  },
  {
    authorId: 'mock-user-amara', authorName: 'Amara Okafor', activity: 'Run',
    caption: 'Track session: 6x800m. Splits felt smooth today.', themeKey: 'sunset',
    metricLabels: ['7.20 km', '34:02', '4:43 /km'], likesCount: 167, commentsCount: 9, hoursAgo: 8,
  },
  {
    authorId: 'mock-user-carlos', authorName: 'Carlos Mendes', activity: 'Status Update',
    caption: 'Sunday century ride is officially booked. Who’s in?', themeKey: 'sunset',
    metricLabels: ['Post', 'Community', 'Now'], likesCount: 58, commentsCount: 22, hoursAgo: 10,
  },
  {
    authorId: 'mock-user-zanele', authorName: 'Zanele Mokoena', activity: 'Strength',
    caption: '8 weeks postpartum, back on the platform. Logged 5 exercises.', themeKey: 'burn',
    metricLabels: ['48 min', '290 kcal', '5 moves'], likesCount: 412, commentsCount: 64, hoursAgo: 13,
  },
  {
    authorId: 'mock-user-jordan', authorName: 'Jordan Kim', activity: 'Meal',
    caption: 'Pre-swim fuel. Oats, banana, almond butter.', themeKey: 'graphite',
    metricLabels: ['410 kcal', '12g protein', '16g fat'], likesCount: 44, commentsCount: 3, hoursAgo: 15,
  },
  {
    authorId: 'mock-user-naledi', authorName: 'Naledi Khumalo', activity: 'Strength',
    caption: 'Leg day. Logged 4 exercises, notes: knees felt good.', themeKey: 'burn',
    metricLabels: ['58 min', '410 kcal', '4 moves'], likesCount: 98, commentsCount: 7, hoursAgo: 18,
  },
  {
    authorId: 'mock-user-sipho', authorName: 'Sipho Dlamini', activity: 'Meal',
    caption: 'Bulking season. Rice, chicken thighs, broccoli.', themeKey: 'graphite',
    metricLabels: ['780 kcal', '58g protein', '22g fat'], likesCount: 53, commentsCount: 4, hoursAgo: 20,
  },
  {
    authorId: 'mock-user-priya', authorName: 'Priya Nair', activity: 'Yoga',
    caption: '60 minute vinyasa flow. Mind feels as loose as my hips.', themeKey: 'sunset',
    metricLabels: ['60 min', '180 kcal', '1 session'], likesCount: 121, commentsCount: 11, hoursAgo: 23,
  },
  {
    authorId: 'mock-user-liam', authorName: 'Liam Foster', activity: 'Run',
    caption: 'Recovery jog around the park before the rain hit.', themeKey: 'sunset',
    metricLabels: ['5.10 km', '28:40', '5:37 /km'], likesCount: 87, commentsCount: 6, hoursAgo: 27,
  },
  {
    authorId: 'mock-user-amara', authorName: 'Amara Okafor', activity: 'Status Update',
    caption: 'Race number for the city half just arrived. Let’s go.', themeKey: 'sunset',
    metricLabels: ['Post', 'Community', 'Now'], likesCount: 233, commentsCount: 27, hoursAgo: 31,
  },
  {
    authorId: 'mock-user-carlos', authorName: 'Carlos Mendes', activity: 'Run',
    caption: 'Brick session: 40km ride into a 5km run.', themeKey: 'burn',
    metricLabels: ['5.00 km', '24:55', '4:59 /km'], likesCount: 142, commentsCount: 14, hoursAgo: 36,
  },
  {
    authorId: 'mock-user-zanele', authorName: 'Zanele Mokoena', activity: 'Meal',
    caption: 'Meal prep Sunday. Five days of lunches done.', themeKey: 'graphite',
    metricLabels: ['610 kcal', '40g protein', '18g fat'], likesCount: 96, commentsCount: 8, hoursAgo: 40,
  },
  {
    authorId: 'mock-user-jordan', authorName: 'Jordan Kim', activity: 'Strength',
    caption: 'Dryland session before tomorrow’s open water swim. Logged 3 exercises.', themeKey: 'burn',
    metricLabels: ['35 min', '220 kcal', '3 moves'], likesCount: 61, commentsCount: 5, hoursAgo: 44,
  },
  {
    authorId: 'mock-user-naledi', authorName: 'Naledi Khumalo', activity: 'Run',
    caption: 'Long run Sunday. 21K done, legs are toast.', themeKey: 'sunset',
    metricLabels: ['21.10 km', '1:48:32', '5:09 /km'], likesCount: 356, commentsCount: 42, hoursAgo: 49,
  },
  {
    authorId: 'mock-user-sipho', authorName: 'Sipho Dlamini', activity: 'Strength',
    caption: 'Upper body push day. Logged 4 exercises, notes: shoulder felt stable.', themeKey: 'burn',
    metricLabels: ['54 min', '380 kcal', '4 moves'], likesCount: 174, commentsCount: 16, hoursAgo: 55,
  },
  {
    authorId: 'mock-user-priya', authorName: 'Priya Nair', activity: 'Meal',
    caption: 'Sunday meal prep: dal, brown rice, roasted veg.', themeKey: 'graphite',
    metricLabels: ['560 kcal', '28g protein', '11g fat'], likesCount: 68, commentsCount: 4, hoursAgo: 62,
  },
  {
    authorId: 'mock-user-liam', authorName: 'Liam Foster', activity: 'HIIT',
    caption: 'Tabata Friday. 8 rounds, no mercy.', themeKey: 'burn',
    metricLabels: ['16 min', '260 kcal', '6 moves'], likesCount: 145, commentsCount: 13, hoursAgo: 70,
  },
  {
    authorId: 'mock-user-amara', authorName: 'Amara Okafor', activity: 'Run',
    caption: 'Hill repeats. 8x200m incline, lungs on fire.', themeKey: 'sunset',
    metricLabels: ['6.40 km', '38:11', '5:58 /km'], likesCount: 109, commentsCount: 10, hoursAgo: 78,
  },
  {
    authorId: 'mock-user-carlos', authorName: 'Carlos Mendes', activity: 'Status Update',
    caption: 'New bike day. Time to put in some serious kilometers.', themeKey: 'sunset',
    metricLabels: ['Post', 'Community', 'Now'], likesCount: 312, commentsCount: 38, hoursAgo: 86,
  },
  {
    authorId: 'mock-user-zanele', authorName: 'Zanele Mokoena', activity: 'Strength',
    caption: 'Full body circuit, logged 5 exercises. Feeling stronger every week.', themeKey: 'burn',
    metricLabels: ['50 min', '330 kcal', '5 moves'], likesCount: 187, commentsCount: 19, hoursAgo: 94,
  },
  {
    authorId: 'mock-user-jordan', authorName: 'Jordan Kim', activity: 'Run',
    caption: 'Easy shakeout before the swim meet this weekend.', themeKey: 'sunset',
    metricLabels: ['4.00 km', '22:10', '5:33 /km'], likesCount: 49, commentsCount: 2, hoursAgo: 102,
  },
];

function timestampLabel(hoursAgo) {
  if (hoursAgo < 24) return `${hoursAgo}h`;
  const days = Math.round(hoursAgo / 24);
  return `${days}d`;
}

const posts = postsByHoursAgo.map((post) => ({
  ...post,
  timestampLabel: timestampLabel(post.hoursAgo),
}));

const progress = [
  {
    label: 'Weekly Volume',
    value: '18,420 kg',
    delta: '+8.2%',
    chartBars: [4200, 4600, 3900, 5100, 4800, 5300, 5600],
  },
  {
    label: 'Avg Pace',
    value: '5:14 /km',
    delta: '-0:11',
    chartBars: [5.45, 5.38, 5.3, 5.25, 5.2, 5.16, 5.14],
  },
  {
    label: 'Calories Burned',
    value: '3,260 kcal',
    delta: '+12%',
    chartBars: [380, 420, 310, 460, 390, 510, 470],
  },
  {
    label: 'Active Minutes',
    value: '312 min',
    delta: '+5.4%',
    chartBars: [38, 45, 30, 52, 41, 58, 48],
  },
];

module.exports = { users, posts, progress };
