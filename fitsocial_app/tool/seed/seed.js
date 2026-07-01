// Seeds the local Firestore emulator with mock FitSocial users, posts, and
// progress metrics so the feed/profile/progress screens have realistic data
// to scroll through during UI and demo testing.
//
// Usage:
//   1. From fitsocial_app/, start the emulator: firebase emulators:start --only firestore
//   2. In another terminal: cd tool/seed && npm install && npm run seed
//
// This script only ever talks to the local emulator (FIRESTORE_EMULATOR_HOST
// below) — it never touches the live fitsocialv2 project and needs no
// credentials.

const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.FIRESTORE_EMULATOR_HOST = EMULATOR_HOST;

const admin = require('firebase-admin');
const { users, posts, progress } = require('./data');

admin.initializeApp({ projectId: 'fitsocialv2' });
const db = admin.firestore();

async function clearMockData() {
  const collections = ['users', 'posts', 'progress'];
  for (const name of collections) {
    const snapshot = await db.collection(name).get();
    const batch = db.batch();
    let deleted = 0;
    snapshot.docs.forEach((doc) => {
      if (doc.id.startsWith('mock-')) {
        batch.delete(doc.ref);
        deleted += 1;
      }
    });
    if (deleted > 0) await batch.commit();
    console.log(`Cleared ${deleted} existing mock doc(s) from "${name}".`);
  }
}

async function seedUsers() {
  const batch = db.batch();
  users.forEach((user) => {
    const { id, ...fields } = user;
    batch.set(db.collection('users').doc(id), {
      ...fields,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  await batch.commit();
  console.log(`Seeded ${users.length} user(s).`);
}

async function seedPosts() {
  const batch = db.batch();
  const now = Date.now();
  posts.forEach((post, index) => {
    const { hoursAgo, ...fields } = post;
    const createdAt = admin.firestore.Timestamp.fromMillis(
      now - hoursAgo * 60 * 60 * 1000,
    );
    batch.set(db.collection('posts').doc(`mock-post-${index}`), {
      ...fields,
      createdAt,
    });
  });
  await batch.commit();
  console.log(`Seeded ${posts.length} post(s).`);
}

async function seedProgress() {
  const batch = db.batch();
  progress.forEach((metric, index) => {
    batch.set(db.collection('progress').doc(`mock-progress-${index}`), metric);
  });
  await batch.commit();
  console.log(`Seeded ${progress.length} progress metric(s).`);
}

async function main() {
  console.log(`Seeding Firestore emulator at ${EMULATOR_HOST} (project: fitsocialv2)...`);
  await clearMockData();
  await seedUsers();
  await seedPosts();
  await seedProgress();
  console.log('Done. Open http://127.0.0.1:4000/firestore to browse the data.');
  process.exit(0);
}

main().catch((error) => {
  console.error('Seeding failed:', error);
  process.exit(1);
});
