// Backfills author attribution on existing posts and comments.
//
// Records written before author names were resolved from the stored profile
// carry the placeholder "FitSocial Member" (or the older "FitSocial User"), and
// none of them carry an author avatar — those fields are denormalised at write
// time, so fixing the write path does not repair history. This script walks the
// existing documents and fills them in from each author's current profile.
//
// UNLIKE tool/seed, THIS TALKS TO THE LIVE fitsocialv2 PROJECT.
// It runs in dry-run mode unless you pass --apply.
//
// Usage:
//   1. Firebase Console -> Project settings -> Service accounts
//      -> "Generate new private key". Save it OUTSIDE the repo.
//   2. set GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\serviceAccountKey.json
//   3. cd tool/backfill && npm install
//   4. npm run backfill          (dry run — prints what would change)
//   5. npm run backfill -- --apply

const admin = require('firebase-admin');

const APPLY = process.argv.includes('--apply');
const PROJECT_ID = 'fitsocialv2';

// Mirrors PublicAuthorName in lib/features/main/domain/app_models.dart. An
// author name is publicly visible, so it must never be an email address.
const FALLBACK = 'FitSocial Member';
const LEGACY_FALLBACK = 'FitSocial User';
const EMAIL_LIKE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

function firstSafe(candidates) {
  for (const candidate of candidates) {
    const trimmed = (candidate || '').trim();
    if (!trimmed) continue;
    if (EMAIL_LIKE.test(trimmed)) continue;
    return trimmed;
  }
  return FALLBACK;
}

/// True when the stored name is a placeholder or an address that leaked in
/// before sanitisation existed. Anything else is a real name we must not touch.
function needsNameRepair(current) {
  const trimmed = (current || '').trim();
  return (
    !trimmed ||
    trimmed === FALLBACK ||
    trimmed === LEGACY_FALLBACK ||
    EMAIL_LIKE.test(trimmed)
  );
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: PROJECT_ID,
});
const db = admin.firestore();

/// userId -> { name, avatarUrl }, read once so the walk below costs one read
/// per user rather than one per post.
async function loadProfiles() {
  const snapshot = await db.collection('users').get();
  const profiles = new Map();
  snapshot.docs.forEach((doc) => {
    const data = doc.data();
    profiles.set(doc.id, {
      name: firstSafe([data.displayName, data.handle]),
      avatarUrl: data.avatarUrl || null,
    });
  });
  console.log(`Loaded ${profiles.size} profile(s).`);
  return profiles;
}

/// Returns the fields that should change on [data], or null if it is already
/// correct. Only ever fills gaps — never overwrites a good value.
function plannedUpdate(data, profiles) {
  const profile = profiles.get(data.authorId);
  if (!profile) return null;

  const update = {};

  if (needsNameRepair(data.authorName) && profile.name !== FALLBACK) {
    update.authorName = profile.name;
  }
  if (!data.authorAvatarUrl && profile.avatarUrl) {
    update.authorAvatarUrl = profile.avatarUrl;
  }

  return Object.keys(update).length > 0 ? update : null;
}

/// Commits in chunks — Firestore caps a batch at 500 writes.
async function commitAll(writes) {
  if (!APPLY) return;
  for (let i = 0; i < writes.length; i += 500) {
    const batch = db.batch();
    writes.slice(i, i + 500).forEach(({ ref, update }) => batch.update(ref, update));
    await batch.commit();
  }
}

async function run() {
  console.log(
    APPLY
      ? `APPLY mode — writing to the live "${PROJECT_ID}" project.`
      : 'DRY RUN — nothing will be written. Pass --apply to commit.'
  );

  const profiles = await loadProfiles();
  const postsSnapshot = await db.collection('posts').get();

  const writes = [];
  let postsChanged = 0;
  let commentsChanged = 0;

  for (const postDoc of postsSnapshot.docs) {
    const update = plannedUpdate(postDoc.data(), profiles);
    if (update) {
      writes.push({ ref: postDoc.ref, update });
      postsChanged += 1;
      console.log(`  post ${postDoc.id}: ${JSON.stringify(update)}`);
    }

    // Comments live in a subcollection per post. Walking them this way avoids
    // needing a collection-group index.
    const commentsSnapshot = await postDoc.ref.collection('comments').get();
    for (const commentDoc of commentsSnapshot.docs) {
      const commentUpdate = plannedUpdate(commentDoc.data(), profiles);
      if (commentUpdate) {
        writes.push({ ref: commentDoc.ref, update: commentUpdate });
        commentsChanged += 1;
        console.log(
          `  comment ${postDoc.id}/${commentDoc.id}: ${JSON.stringify(commentUpdate)}`
        );
      }
    }
  }

  await commitAll(writes);

  console.log('');
  console.log(`Scanned ${postsSnapshot.size} post(s).`);
  console.log(`${postsChanged} post(s) and ${commentsChanged} comment(s) need repair.`);
  console.log(APPLY ? 'Committed.' : 'Dry run complete — re-run with --apply to commit.');
}

run().then(
  () => process.exit(0),
  (error) => {
    console.error('Backfill failed:', error.message);
    process.exit(1);
  }
);
