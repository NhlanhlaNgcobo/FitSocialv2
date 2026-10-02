# Build 11 handoff

**For:** whoever picks Build 11 up next, including a fresh Claude Code session on another machine.
**Last updated:** 2026-10-02. P0, F1, F2, F3, F4, F6 and the Live Share purge are pushed **and deployed**, all flags off. F5 Recap Cards is app-only and on `feat/recap-cards`.
**Spec:** `FitSocial_Build11_Spec.md` (Bear's copy, kept outside the repo). This file records how that spec was reconciled with the code, what is done, and what is left.

A new Claude Code session should read this file first, then `HANDOFF.md` and `CODEBASE_ANALYSIS.md` for the wider app.

---

## 1. Decisions Bear made

| Topic | Decision |
|---|---|
| Scope | P0 groundwork + Phase 1 (Goals/Challenges, Compare, friends Leaderboards) + Phase 2 (Weekly Insights, Up Next, Recap Cards). Effort Score and paid plans move to Build 12+. |
| Feature flags | Firebase Remote Config. Every Build 11 feature is off until switched on in the console. The server reads the same parameters. |
| Git | One short branch per feature, merged into `main` once analyze and all tests pass, then deleted. Push only when Bear asks. |
| Blocking | Deferred. There is no block system; leaderboards are followed-users-only with an opt-out. |
| Analytics | On since 2026-09-30 (`AppConfig.enableAnalytics = true`). Bear still has to update the Play Data Safety form. |
| Instagram Stories | Wanted for Recap Cards (F5), as well as the system share sheet. Check Meta's current sharing rules before building. |
| AI provider | OpenRouter, through the existing `OPENROUTER_API_KEY` secret in Cloud Functions. Not OpenAI directly. |
| Still open | Can under-18s sign up? ZAR pricing and billing vendor (Build 12).  |

### How the spec was reconciled with the code

The spec was written without seeing the repo, and much of it already existed. Build 11 extends what is there rather than adding parallel copies:

- **Health data:** extends `dailySteps/{uid}_{dayKey}` instead of a new `healthDaily` collection.
- **Timezones:** keeps `ChallengeClock`'s UTC-offset minutes instead of IANA zone names (no tz database in Flutter; South Africa has no DST).
- **Challenges:** new activity challenges live in the existing `challenges` collection as `type: 'activity'` and reuse its participants, invitations and finalise job.
- **Achievements:** the existing badge system already matched the spec (server-evaluated, server-written), so new badges were added to it.
- **Live Share:** already exists (`locationShares`). The only Build 11 work left is purging the last position after a share ends.

---

## 2. Status

| Item | Status | Flag |
|---|---|---|
| P0: shared week/month keys (Dart + Node, one fixture file) | Done, pushed | none |
| P0: Remote Config flags + analytics events | Done, pushed | none |
| P0: `dailySteps` gains `manualSteps`, heart rate, offset | Done, pushed | none |
| F1: server stats pipeline (`dailyStats`, `weeklyStats`, `monthlyStats`) | Done, pushed | any reader flag |
| F1: personal goals (screen + home card) | Done, pushed | `f1_goals_challenges` |
| F1: activity challenges (steps / minutes / sessions / meals) | Done, pushed | `f1_goals_challenges` |
| F1: final places, `challengeResult` notification, 6 new badges | Done, pushed | also affects running challenges |
| F4: Compare card on the Progress tab | Done, pushed | `f4_compare` |
| F6: friends leaderboards | Done, pushed | `f6_leaderboards` |
| Live Share: purge ended shares' positions | Done (`onLocationShareUpdated` + `expireShares`), not deployed | none |
| F2: Weekly Insights (AI) | Done, pushed, deployed | `f2_weekly_insights` |
| F3: Up Next | Done, pushed, deployed | `f3_up_next` |
| F5: Recap Cards | Done, app-only (nothing to deploy); Instagram Stories button deferred | `f5_recap_cards` |
| Build number 10 to 11 in `pubspec.yaml` | Not done | do it last |

Rules, indexes and every function up to the Live Share purge were deployed to fitsocialv2 on 2026-10-02, with every flag still off. Nothing has been switched on or run on a phone yet.

---

## 3. Where things are

**Server (`fitsocial_app/functions/`)**
- `period_keys.js`: ISO week and month keys. Twin of `lib/shared/time/period_keys.dart`.
- `remote_config.js`: the server's read of the Remote Config flags and ceilings, cached 5 minutes.
- `stats.js`: rebuilds a day's stats from runs, workouts, meals and `dailySteps`, then its week and month. Idle while every reader flag is off.
- `goals.js`: `createGoal` callable, progress per period, nightly `rollGoalPeriods` job.
- `activity_ranking.js`: pure ranking rules for activity challenges.
- `activity_challenges.js`: activity challenge engine and `recordResults` (final places, badges, result notifications) for every challenge type.
- `leaderboard.js`: the followers-readable projection of a week's or month's
  stats (`leaderboardEntries/{uid}_{periodId}`), and the trigger that acts on
  the opt-out. Registered as a `stats.onDayChanged` listener, so it has to be
  required after `stats.js` in `index.js`.
- `scripts/backfill_stats.js`: builds the last 70 days of stats. **Not run yet**: it needs admin credentials this laptop does not have. Bear may prefer it as a one-off Cloud Function instead.

**App (`fitsocial_app/lib/`)**
- `core/config/feature_flags.dart`: `FeatureFlag`, `Tunable`, `featureEnabledProvider`.
- `core/observability/app_analytics.dart`: every product event, in one enum.
- `features/goals/`: goals model, repository, providers, screen, home card.
- `features/compare/`: Compare logic, repository, card.
- `features/leaderboards/`: the ranking (pure), the entry repository, the board
  screen at `/leaderboard`, and the preview card on the Progress tab.
- `features/challenges/domain/running_challenge.dart`: now also carries `ChallengeKind`, `ActivityMetric`, `ActivityMode`.
- `features/challenges/domain/daily_health.dart`: how a day's health reading merges into `dailySteps`.

**Rules and indexes:** `firestore.rules` (stats, goals, activity challenges, and the participant-row guard) and `firestore.indexes.json` (collection-group index on `goals.status`).

---

## 4. Before switching anything on

1. Deploy rules, indexes and functions:
   ```bash
   npx firebase-tools deploy --only firestore:rules,firestore:indexes,functions --project fitsocialv2
   ```
2. In Remote Config, add the flag (`f1_goals_challenges`, `f4_compare`, ...) as a boolean, set it to `true`, and publish.
3. Optionally backfill stats so Compare has history on day one (see §3).

---

## 5. Working conventions (these trip people up)

- **Commits:** lowercase conventional commits that name the behaviour ("feat: compare this week ..."), with the reasoning in the body. **No `Co-Authored-By` trailer and no "Generated with Claude Code" line, ever.**
- **Shared checkout:** other sessions may be editing `fitsocial_app` at the same time. Run `dart format` only on files you edited, never a folder. Never bulk-revert or stash.
- **Worktrees:** a fresh worktree lacks the gitignored `lib/firebase_options.dart` and `android/key.properties`. Copy them in from the main checkout before analyzing or building.
- **Scheduled functions** must set `region: "us-central1"`. Cloud Scheduler does not exist in `africa-south1` and the deploy fails otherwise.
- **Tests, and how to run them on Windows:**
  - App: `flutter analyze` and `flutter test` from `fitsocial_app/`.
  - Functions: `node --test` from `fitsocial_app/functions/`. `npm test` fails here because npm's shell cannot find `node`.
  - Rules: from `fitsocial_app/test_rules/`, in **PowerShell** with Java on the path (see `test_rules/README.md`):
    ```powershell
    $env:JAVA_HOME = 'C:\Java\jdk-21'; $env:Path = "$env:JAVA_HOME\bin;" + $env:Path
    firebase emulators:exec --only firestore --project fitsocial-rules-test "node --test --test-concurrency=1"
    ```
  - Last green run **with F6**: 1,778 app tests, 228 Functions tests, 170 rules
    tests. The rules count includes `routines.test.mjs`, which belongs to the
    workout work another session is doing in this checkout, not to F6.

---

## 6. F6 friends leaderboards, as built

Weekly and monthly boards among the people you follow, on four figures — steps,
active minutes, sessions and best streak — with an opt-out, deterministic ties,
hand-typed and implausible days excluded, and a fixed number of reads.

**The projection is the whole design.** `weeklyStats` and `monthlyStats` stay
owner-only. `functions/leaderboard.js` copies the four rankable figures, plus
`activeDays` as the tiebreak, into `leaderboardEntries/{uid}_{periodId}`, which
`firestore.rules` opens to the owner and to the people who follow them. Meals,
heart rate, raw and hand-typed steps and the per-day series never leave the stats
documents. Integrity needed no new code: an entry copies `rankableSteps` and
`rankableActiveMinutes`, which stats.js has already netted of hand-typed steps
and zeroed for a day over the Remote Config ceiling.

Decisions worth knowing before changing any of it:

- **A period with nothing in it has no entry.** Not a row of zeros: a week nobody
  logged anything in is somebody who was not playing, not a last place. A period
  emptied by a deleted workout deletes its entry rather than leaving stale
  figures standing.
- **Nobody appears on a board they have no figure for.** Three sessions and no
  step sync puts you on the sessions board and leaves you off the steps board,
  where a 0 would read as a week spent sitting down.
- **Equal figures share a rank** (1, 2, 2, 4), ordered within the tie by active
  days and then by user id — fixed, so a board never reshuffles between
  refreshes. The id fallback is the one activity challenges already use.
- **The viewer is always on their own board**, pinned under the top 50 at their
  real rank, the same way the challenge board pins its own row.
- **Opt-out is `users/{uid}.leaderboardOptOut`.** Setting it purges every entry
  that user has, *whether or not the flag is on* — entries written while it was up
  outlive it coming down, and somebody asking to be taken off is owed that.
  Clearing it rebuilds the current week and month only; finished boards somebody
  sat out stay sat out.
- **Ten uids per query, not thirty.** The rule does a follower lookup per
  returned document and the rules engine allows 20 per query, identical ones
  cached. Same constraint, same number, as the Pulse tray.
- **Entries are read by document id**, which `{uid}_{periodId}` makes possible, so
  a board needs no composite index and somebody with no entry costs nothing.
- The board is a `FutureProvider`, not a stream: pull down to refresh. A live
  listener per chunk would be five sockets for figures that move a few times a
  day.
- `account_deletion.js` now also purges `dailyStats`, `weeklyStats`,
  `monthlyStats` and `leaderboardEntries`. The first three were a gap left by F1
  — a deleted account was keeping its step history in documents nothing would
  ever rebuild — and the last is the only one other people can read, so a board
  would otherwise go on ranking somebody who is gone.

Where the UI is: `/leaderboard`, reached from a preview card under Compare on the
Progress tab. The card draws only on the current week or month — there is no board
to page back to — and nothing at all while the flag is off or the board is empty.
The opt-out switch is on the board screen itself, worded "Show me on
leaderboards" rather than as an opt-out, and it has to live there: opting out
empties the screen above it, so a switch anywhere else would be the only way
back on.

Left out deliberately: no leaderboard notifications, no paging to past periods,
and no backfill — so a board stays empty until the stats pipeline has run for a
day with the flag on, or `scripts/backfill_stats.js` has been run (§3).

## 7. The other session's workout work is still in this tree

F6 was committed as `7d97b12` with its own files only. Everything still showing
as modified or untracked in `fitsocial_app` belongs to another session's workout
work, which was in flight at the same time and is **not finished** — at one point
it had `firestore_content_repository.dart` importing a `meal_quality.dart` that
did not exist, which broke every `flutter test` until it was backed out.

What is theirs, as of F6's commit:

```
lib/features/main/domain/{active_workout,exercise_library,workout_math,workout_models}.dart
lib/features/main/application/{active_workout_controller,workout_library_providers}.dart
lib/features/main/data/active_workout_store.dart
lib/features/main/presentation/{workout_session_screen,exercise_picker_sheet,custom_exercise_sheet}.dart
lib/features/main/{data/content_repository*.dart,data/firestore_content_repository.dart,domain/app_models.dart}
lib/features/main/presentation/create_screen.dart
test/{active_workout,workout_math,workout_session_screen,workout_sets_model}_test.dart
test_rules/routines.test.mjs
```

and, inside four files F6 also touched, these additions which are theirs alone:

| File | Theirs |
|---|---|
| `firestore.rules` | the `/routines` and `/customExercises` blocks |
| `functions/account_deletion.js` | purging `routines` and `customExercises` |
| `functions/test/account_deletion.test.js` | the `routines`/`customExercises` seed and assertions |
| `lib/app/router/app_router.dart` | the `/workout-session` route and its import |

So `git diff` on those four shows their work and nothing else. Do not stage them
wholesale into an F6 follow-up, and do not revert or stash any of it.

## 8. Next: Phase 2


The Live Share purge is done: `onLocationShareUpdated` in `functions/safety.js`
deletes `current` once a share is no longer active, and `expireShares` drops it in
the same write that expires a share. Shares that ended before it is deployed keep
their last position until somebody clears them by hand. Next is Phase 2 — F2
Weekly Insights (AI, through the existing `OPENROUTER_API_KEY`), F3 Up Next and
F5 Recap Cards — and the build number bump to 11, last of all.

## 9. F2 Weekly Insights, as built

`functions/insights.js`, `lib/features/insights/`, rules for `users/{uid}/insights`
and `insightFeedback`, and tests in all three suites.

- **Model:** `anthropic/claude-haiku-4.5` through OpenRouter, Bear's choice as the
  cheapest. Override with `INSIGHTS_MODEL` in `functions/.env`. Same
  `OPENROUTER_API_KEY` secret as the meal analyzer.
- **When:** `generateWeeklyInsights` runs Mondays 05:00 SAST (us-central1) for
  everybody with at least two days of data last week who has not hidden the
  feature. The app also calls `requestWeeklyInsight` once when it finds no insight
  stored, so nobody waits a week after the flag goes on.
- **Cost controls:** one insight per user per week, cached on uid + weekId +
  `PROMPT_VERSION`; a week with fewer than two days of data never calls the model;
  two regenerations per user per day; a transaction claim so the job and a tap
  cannot both pay for the same week; three attempts at most, with backoff.
- **Privacy:** the model gets aggregates only, copied field by field
  (`buildPayload`, asserted key by key in the tests). No uid, names, places, free
  text or calories.
- **Safety:** the reply has to parse, match the output contract and pass a list
  of banned patterns (calories, weight, restriction, fasting, "cheat", medical
  words...). It is tested against adversarial replies. A failed reply is stored
  as `failed` with no content, and the app shows nothing.
- **Wellbeing note:** set on the server when at least four days each have two or
  more meals logged and average under 1,000 kcal. The app then shows
  `kWellbeingNote`. Bear signed off the wording on 2026-10-02; the
  threshold is Claude's and can be tuned without a new sign-off.
- **Client:** home card under Goals, `/insights` detail screen (wins, trends,
  suggestion, feedback chips, "Report as offensive", "Write a new one", "Hide"),
  and a Settings switch that only exists while the flag is on.

Left out: challenge progress in the payload (goals only), and any push
notification when an insight is ready.

## 10. F3 Up Next, as built

`functions/up_next.js`, `lib/features/up_next/`, rules for `users/{uid}/upNext`,
tests in all three suites.

- **Rule-based, no AI** (spec: start rule-based). Four rules, in the order they
  win one of three places: a streak of 2+ days at risk after 15:00; a weekly
  goal today can close (steps within 6,000 -- "a 25-minute walk" at 100 steps a
  minute -- minutes within 60, one session, meals within 3); no meal logged
  between 12:00 and 21:00 for somebody who logged on 3 of the last 7 days; no
  session by Wednesday for somebody who trained in the fortnight before.
- Nothing for somebody with no data in the last 14 days.
- Rebuilt on every change to today's stats (a `stats.onDayChanged` listener,
  required after goals.js so goal progress is current) and by the
  `refreshUpNext` callable, which the app calls when home appears and on resume,
  at most every 15 minutes. No schedule: the time-of-day rules only matter to
  somebody looking at the app.
- Dismissal is the owner adding an id to `dismissed`; rules allow only that,
  only growing, at most 20. Rebuilds filter dismissed ids out, so a swiped card
  does not come back that day.
- Every suggestion's text goes through the Weekly Insights safety filter in the
  tests.

Left out: the spec's "challenge lead change" rule. It needs a ranking history
nothing keeps yet.

## 11. F5 Recap Cards, as built

App-only: `lib/features/recap/`. No server code, no new collections, nothing to
deploy. Ships with the next app build.

- Three cards, each a 1080 x 1920 PNG drawn off screen the way the run, meal and
  workout cards already are: **last week** ("Share last week" on the Progress
  tab, under the leaderboard card), a **finished challenge** ("Share result" on
  your own row of a finished activity challenge), and a **badge** ("Share" in
  the badge sheet on Achievements).
- A sheet with a live preview and switches: name (on), numbers (on), heart rate
  (**off** by default, and only with numbers on). Challenge cards carry only the
  sharer's own place and result -- there is no parameter for anybody else's.
- One fixed dark design whatever the app theme, since the image goes to someone
  else's feed. Tested for overflow on small and large screens in both themes.
- Shared through the system share sheet. `recap_generated` when the image is
  drawn, `recap_shared` with the picked app's package when the platform says.
- **Instagram Stories button: deferred by Bear.** Meta's Stories intent
  (`com.instagram.share.ADD_TO_STORY`) refuses shares without a registered Meta
  App ID in `source_application`. When Bear has one, add the button to the
  recap sheet, hidden while the ID is unset.
