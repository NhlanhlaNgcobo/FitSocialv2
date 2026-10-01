# Build 11 handoff

**For:** whoever picks Build 11 up next, including a fresh Claude Code session on another machine.
**Last updated:** 2026-10-01, at commit `bb3a476` on `main`.
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
| Still open | Can under-18s sign up? ZAR pricing and billing vendor (Build 12). Exact wording of the "talk to a professional" message in Weekly Insights. |

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
| F6: friends leaderboards | **Next** | `f6_leaderboards` |
| Live Share: purge ended shares' positions | Not started | none |
| F2: Weekly Insights (AI) | Not started | `f2_weekly_insights` |
| F3: Up Next | Not started | `f3_up_next` |
| F5: Recap Cards (+ Instagram Stories) | Not started | `f5_recap_cards` |
| Build number 10 to 11 in `pubspec.yaml` | Not done | do it last |

Nothing from Build 11 has been run on a phone or against the live Firebase project yet. All of it is tested locally (see §5).

---

## 3. Where things are

**Server (`fitsocial_app/functions/`)**
- `period_keys.js`: ISO week and month keys. Twin of `lib/shared/time/period_keys.dart`.
- `remote_config.js`: the server's read of the Remote Config flags and ceilings, cached 5 minutes.
- `stats.js`: rebuilds a day's stats from runs, workouts, meals and `dailySteps`, then its week and month. Idle while every reader flag is off.
- `goals.js`: `createGoal` callable, progress per period, nightly `rollGoalPeriods` job.
- `activity_ranking.js`: pure ranking rules for activity challenges.
- `activity_challenges.js`: activity challenge engine and `recordResults` (final places, badges, result notifications) for every challenge type.
- `scripts/backfill_stats.js`: builds the last 70 days of stats. **Not run yet**: it needs admin credentials this laptop does not have. Bear may prefer it as a one-off Cloud Function instead.

**App (`fitsocial_app/lib/`)**
- `core/config/feature_flags.dart`: `FeatureFlag`, `Tunable`, `featureEnabledProvider`.
- `core/observability/app_analytics.dart`: every product event, in one enum.
- `features/goals/`: goals model, repository, providers, screen, home card.
- `features/compare/`: Compare logic, repository, card.
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
  - Last green run: 1,718 app tests, 218 Functions tests, 151 rules tests.

---

## 6. Next: F6 friends leaderboards

What the spec asks: weekly and monthly leaderboards among the people you follow, for steps, active minutes, sessions and streaks, with an opt-out, deterministic ties, hand-typed steps and implausible days excluded, and a bounded number of reads.

What already exists to build on:
- `weeklyStats` / `monthlyStats` already hold rankable figures (`rankableSteps`, `rankableActiveMinutes`, `sessions`, `longestStreak`).
- These documents are owner-read-only, deliberately. A leaderboard needs friends' figures, so plan a small, public-to-followers projection (for example `leaderboardEntries/{uid}_{periodId}` holding only the ranked numbers and the opt-out) rather than opening the stats documents.
- The follow graph is `users/{uid}/following`. Firestore `in` queries take up to 30 values, so chunk and cap the board (for example top 50).
- Analytics events already exist: `leaderboard_viewed`, `leaderboard_filter_changed`, `leaderboard_optout_toggled`.

After F6: the Live Share purge, then Phase 2 (F2, F3, F5).
