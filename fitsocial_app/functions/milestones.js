/**
 * Milestones: the feed posts nobody had to write.
 *
 * A feed made only of logs is people reporting to each other. The moments
 * worth talking about -- a seven-day streak, a finished Pulse 75, the longest
 * run somebody has ever done -- were already being computed and then kept on
 * a profile shelf nobody else looks at. This puts them where the people who
 * would say "let's go" can see them.
 *
 * Each one is an ordinary document in `posts`, authored by the person who
 * earned it, with `postType: "milestone"` and a `milestone` map describing it.
 * Being a post is the whole design: reactions, comments, notifications, the
 * feed query and the follow graph all apply without a line of new plumbing.
 * A build that predates the type reads `milestone` as `text` and shows the
 * caption, which is written to stand on its own for exactly that reason.
 *
 * Written here rather than by the client because every source is either
 * server-owned already (badges) or needs a history the client does not hold
 * (personal bests). The streak is client-written, but deciding "that was a
 * milestone" in one place beats teaching two write paths to agree.
 *
 * Nothing is posted for somebody who has turned `shareMilestones` off, and a
 * personal best is only announced for a run its author shared to the feed --
 * a milestone must never be how a private run becomes public.
 *
 * Document ids are deterministic, so a retried trigger finds its own post and
 * stops instead of writing a second one.
 */

const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

// The memoised accessor from the challenge engine -- see `db()` there for why a
// second initialisation guard must never be written.
const { db } = require("./challenges")._internals;

// --- What counts ------------------------------------------------------------

/**
 * Streak lengths worth a post. Front-loaded on purpose: day three is where most
 * habits die, and a cheer then is worth more than one at day 300.
 */
const STREAK_MILESTONES = [3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 250, 300, 365];

/** The streak milestone [after] reached that [before] had not, or null. */
function crossedStreakMilestone(before, after) {
  const from = Number(before) || 0;
  const to = Number(after) || 0;
  if (to <= from) return null;
  let crossed = null;
  for (const milestone of STREAK_MILESTONES) {
    if (from < milestone && to >= milestone) crossed = milestone;
  }
  // Past a year, every hundred days.
  if (to > 365 && Math.floor(to / 100) > Math.floor(from / 100)) {
    crossed = Math.floor(to / 100) * 100;
  }
  return crossed;
}

/**
 * The copy for each badge. Titles match ChallengeBadge.label on the client;
 * the lines are written for somebody else's feed, so they say what the person
 * did rather than congratulating them.
 */
const BADGE_COPY = {
  PULSE_DAY_ONE: { title: "Day One", line: "Started Pulse 75", emoji: "\u{1F331}" },
  PULSE_FIRST_WEEK: { title: "First Week", line: "7 days straight on Pulse 75", emoji: "\u{1F4C5}" },
  PULSE_LOCKED_IN: { title: "Locked In", line: "21 days straight on Pulse 75", emoji: "\u{1F512}" },
  PULSE_IRON_MONTH: { title: "Iron Month", line: "30 days straight on Pulse 75", emoji: "\u{1F9BE}" },
  PULSE_HALFWAY: { title: "Halfway", line: "Past the middle of Pulse 75", emoji: "\u{26F0}\u{FE0F}" },
  PULSE_THE_GRIND: { title: "The Grind", line: "50 days of Pulse 75 done", emoji: "\u{2699}\u{FE0F}" },
  PULSE_COMEBACK: { title: "Comeback", line: "Lost a streak and rebuilt it to 14 days", emoji: "\u{1F504}" },
  PULSE_75_FINISHER: { title: "Pulse 75 Finisher", line: "75 of 75 days. Done.", emoji: "\u{1F3C6}" },
  PULSE_FLAWLESS: { title: "Flawless", line: "75 days without missing one", emoji: "\u{1F48E}" },
  EARLY_WORM: { title: "Early Worm", line: "Posted a Pulse before 6 AM", emoji: "\u{1F305}" },
  EARLY_WORM_DAWN_PATROL: { title: "Dawn Patrol", line: "7 early mornings in a row", emoji: "\u{1F304}" },
  EARLY_WORM_SUNRISE: { title: "Sunrise Society", line: "30 early mornings in a row", emoji: "\u{2600}\u{FE0F}" },
  EARLY_WORM_4AM_CLUB: { title: "The 4AM Club", line: "100 early mornings in a row", emoji: "\u{1F319}" },
  FIRST_PULSE: { title: "First Pulse", line: "Published a first Pulse", emoji: "\u{26A1}" },
  POINTS_CENTURY: { title: "Century", line: "Earned 100 points", emoji: "\u{1F4AF}" },
  POINTS_MACHINE: { title: "Point Machine", line: "Earned 10,000 points", emoji: "\u{1F680}" },
  SUPPORTER: { title: "Supporter", line: "Cheered on 100 posts", emoji: "\u{1F4E3}" },
};

function badgeMilestone(badgeKey) {
  const copy = BADGE_COPY[badgeKey];
  if (!copy) return null;
  return {
    kind: "badge",
    key: badgeKey,
    title: copy.title,
    subtitle: copy.line,
    emoji: copy.emoji,
  };
}

function streakMilestone(days) {
  return {
    kind: "streak",
    key: `streak_${days}`,
    title: `${days}-day streak`,
    subtitle: `Showed up ${days} days in a row`,
    emoji: "\u{1F525}",
    value: days,
  };
}

// --- Personal bests ---------------------------------------------------------

/** Prior runs needed before a best means anything. A first run beats nothing. */
const MIN_PRIOR_RUNS = 3;

/** Shortest run whose pace can stand as a best -- a 400m sprint is not one. */
const PACE_MIN_KM = 5;

/** Only runs: hikes and rides carry an `activityType`, runs never do. */
function isRun(data) {
  return !data.activityType || data.activityType === "run";
}

function paceSecondsPerKm(data) {
  const km = Number(data.distanceKm) || 0;
  const seconds = Number(data.durationSeconds) || 0;
  if (km <= 0 || seconds <= 0) return null;
  return seconds / km;
}

function formatPace(secondsPerKm) {
  const rounded = Math.round(secondsPerKm);
  const minutes = Math.floor(rounded / 60);
  const seconds = String(rounded % 60).padStart(2, "0");
  return `${minutes}:${seconds} /km`;
}

function formatKm(km) {
  return `${(Math.round(km * 10) / 10).toFixed(1)} km`;
}

/**
 * The bests [run] sets against [priorRuns], as milestone descriptions.
 *
 * Both lists hold plain run documents. At most one of each kind; a run that is
 * both the longest and the fastest reports both, and each becomes its own post
 * so each can be cheered on its own.
 */
function personalBests(run, priorRuns) {
  if (!isRun(run)) return [];
  const prior = priorRuns.filter(isRun);
  if (prior.length < MIN_PRIOR_RUNS) return [];

  const bests = [];
  const km = Number(run.distanceKm) || 0;

  const longestBefore = Math.max(0, ...prior.map((r) => Number(r.distanceKm) || 0));
  if (km > longestBefore && longestBefore > 0) {
    bests.push({
      kind: "personalBest",
      key: "longest_run",
      title: "Longest run yet",
      subtitle: `${formatKm(km)}, up from ${formatKm(longestBefore)}`,
      emoji: "\u{1F3C3}",
      value: km,
    });
  }

  const pace = km >= PACE_MIN_KM ? paceSecondsPerKm(run) : null;
  if (pace != null) {
    const priorPaces = prior
      .filter((r) => (Number(r.distanceKm) || 0) >= PACE_MIN_KM)
      .map(paceSecondsPerKm)
      .filter((p) => p != null);
    // Needs something to beat: the first 5K is a first, not a best.
    if (priorPaces.length > 0 && pace < Math.min(...priorPaces)) {
      bests.push({
        kind: "personalBest",
        key: "fastest_5k_pace",
        title: "Fastest 5K+ pace",
        subtitle: `${formatPace(pace)} over ${formatKm(km)}`,
        emoji: "\u{26A1}",
        value: Math.round(pace),
      });
    }
  }

  return bests;
}

// --- Writing the post -------------------------------------------------------

/**
 * A public name for [user], never an email. Mirrors PublicAuthorName on the
 * client: posts are readable by every signed-in user.
 */
function publicName(user) {
  const emailLike = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
  for (const candidate of [user.displayName, user.username, user.handle]) {
    const trimmed = typeof candidate === "string" ? candidate.trim() : "";
    if (trimmed && !emailLike.test(trimmed)) return trimmed.replace(/^@/, "");
  }
  return "FitSocial Member";
}

/** The sentence an older build shows in place of the card. */
function fallbackCaption(milestone) {
  return `${milestone.emoji} ${milestone.title} — ${milestone.subtitle}`;
}

function milestonePostId(userId, milestone, occurrence) {
  const suffix = occurrence ? `_${occurrence}` : "";
  return `ms_${userId}_${milestone.key}${suffix}`.replace(/[^A-Za-z0-9_-]/g, "_");
}

/**
 * Posts [milestone] for [userId] unless they have opted out or it is already
 * posted. Returns the post id written, or null.
 *
 * [occurrence] separates milestones that can recur -- a second 7-day streak a
 * month after the first is still worth a post -- and is left off for ones that
 * happen once.
 */
async function publishMilestone(userId, milestone, { occurrence, sourceId } = {}) {
  const userSnap = await db().collection("users").doc(userId).get();
  if (!userSnap.exists) return null;
  const user = userSnap.data() || {};
  if (user.shareMilestones === false) return null;

  const postId = milestonePostId(userId, milestone, occurrence);
  const ref = db().collection("posts").doc(postId);
  if ((await ref.get()).exists) return null;

  await ref.set({
    authorId: userId,
    authorName: publicName(user),
    ...(user.avatarUrl ? { authorAvatarUrl: user.avatarUrl } : {}),
    postType: "milestone",
    activity: "New milestone",
    caption: fallbackCaption(milestone),
    metricLabels: [],
    milestone: {
      ...milestone,
      ...(sourceId ? { sourceId } : {}),
    },
    likesCount: 0,
    commentsCount: 0,
    likedBy: [],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return postId;
}

// --- Triggers ---------------------------------------------------------------

exports.onBadgeAwardedMilestone = onDocumentCreated(
  "users/{userId}/badges/{badgeKey}",
  async (event) => {
    const milestone = badgeMilestone(event.params.badgeKey);
    if (!milestone) return;
    await publishMilestone(event.params.userId, milestone);
  }
);

exports.onStreakMilestone = onDocumentUpdated(
  "users/{userId}",
  async (event) => {
    const before = event.data?.before?.data() || {};
    const after = event.data?.after?.data() || {};
    const days = crossedStreakMilestone(before.currentStreak, after.currentStreak);
    if (!days) return;
    // Keyed by the day it was reached, so a streak rebuilt later earns its
    // post again while a same-day recompute finds the one already written.
    await publishMilestone(event.params.userId, streakMilestone(days), {
      occurrence: after.lastActivityDay || null,
    });
  }
);

exports.onRunPersonalBest = onDocumentCreated("runs/{runId}", async (event) => {
  const run = event.data?.data();
  if (!run || !run.authorId) return;
  if (run.sharedToFeed !== true) return;

  const history = await db()
    .collection("runs")
    .where("authorId", "==", run.authorId)
    .get();
  const prior = history.docs
    .filter((doc) => doc.id !== event.params.runId)
    .map((doc) => doc.data());

  for (const best of personalBests(run, prior)) {
    await publishMilestone(run.authorId, best, {
      occurrence: event.params.runId,
      sourceId: event.params.runId,
    });
  }
});

exports._internals = {
  crossedStreakMilestone,
  badgeMilestone,
  streakMilestone,
  personalBests,
  publishMilestone,
  milestonePostId,
  publicName,
  formatPace,
  BADGE_COPY,
};
