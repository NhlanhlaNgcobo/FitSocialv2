// What sign-up writes: the private fitness profile, weeklyGoalDays on the
// user document, and the weigh-in history the body-metric prompts seed.
//
// The fitness profile is validated because the workout matrix treats its
// goal and equipment as hard constraints -- a value it does not know matches
// no workout at all. Weigh-ins are health data, so only their owner sees them.
import fs from "node:fs";
import test, { before, after, beforeEach } from "node:test";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import {
  doc,
  setDoc,
  getDoc,
  updateDoc,
  deleteDoc,
  writeBatch,
  serverTimestamp,
} from "firebase/firestore";

const ME = "new-user";
const OTHER = "someone-else";
const FITNESS = `users/${ME}/private/fitness`;

const goodProfile = {
  primaryGoal: "buildMuscle",
  secondaryFocus: "chest",
  fitnessLevel: "intermediate",
  activityLevel: "moderate",
  equipment: ["dumbbells"],
  dietType: "omnivore",
  allergies: [],
  targetWeightKg: null,
};

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "fitsocial-rules-test",
    firestore: {
      rules: fs.readFileSync(
        new URL("../firestore.rules", import.meta.url),
        "utf8"
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

after(() => env.cleanup());

beforeEach(() => env.clearFirestore());

const mine = () => env.authenticatedContext(ME).firestore();
const theirs = () => env.authenticatedContext(OTHER).firestore();

// The profile and its username reservation, in one batch -- the only way a
// user document can be created.
function createProfile(db, extra = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, `users/${ME}`), {
    displayName: "Neo M.",
    handle: "neomotion",
    ...extra,
  });
  batch.set(doc(db, "usernames/neomotion"), {
    uid: ME,
    claimedAt: serverTimestamp(),
  });
  return batch.commit();
}

// ---- private/fitness ----

test("the owner can write a full fitness profile", async () => {
  await assertSucceeds(setDoc(doc(mine(), FITNESS), goodProfile));
});

test("the fitness profile is written before the user document exists", async () => {
  // Flush order: fitness first, profile second. Nothing here may depend on
  // users/{uid} already being there.
  await assertSucceeds(
    setDoc(doc(mine(), FITNESS), {
      primaryGoal: "mobilityFitness",
      fitnessLevel: "beginner",
      equipment: ["none"],
    })
  );
});

test("skipped optional fields may be null or absent", async () => {
  await assertSucceeds(
    setDoc(doc(mine(), FITNESS), {
      ...goodProfile,
      secondaryFocus: null,
      activityLevel: null,
      dietType: null,
    })
  );
});

test("the owner can read their fitness profile, nobody else can", async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), FITNESS), goodProfile)
  );
  await assertSucceeds(getDoc(doc(mine(), FITNESS)));
  await assertFails(getDoc(doc(theirs(), FITNESS)));
});

test("nobody else can write someone's fitness profile", async () => {
  await assertFails(setDoc(doc(theirs(), FITNESS), goodProfile));
});

test("an unknown goal is refused", async () => {
  await assertFails(
    setDoc(doc(mine(), FITNESS), { ...goodProfile, primaryGoal: "flyToTheMoon" })
  );
});

test("an unknown focus, level, activity or diet is refused", async () => {
  for (const bad of [
    { secondaryFocus: "ears" },
    { fitnessLevel: "godlike" },
    { activityLevel: "asleep" },
    { dietType: "carnivore" },
  ]) {
    await assertFails(setDoc(doc(mine(), FITNESS), { ...goodProfile, ...bad }));
  }
});

test("equipment must be a non-empty list of known items", async () => {
  for (const equipment of [[], ["spaceship"], "dumbbells", ["none", "rack"]]) {
    await assertFails(
      setDoc(doc(mine(), FITNESS), { ...goodProfile, equipment })
    );
  }
  await assertSucceeds(
    setDoc(doc(mine(), FITNESS), {
      ...goodProfile,
      equipment: ["dumbbells", "homeGym"],
    })
  );
});

test("the required fields cannot be left out", async () => {
  const { primaryGoal, ...noGoal } = goodProfile;
  await assertFails(setDoc(doc(mine(), FITNESS), noGoal));
  const { equipment, ...noEquipment } = goodProfile;
  await assertFails(setDoc(doc(mine(), FITNESS), noEquipment));
});

test("extra fields are refused", async () => {
  await assertFails(
    setDoc(doc(mine(), FITNESS), { ...goodProfile, heightCm: 180 })
  );
});

test("a target weight must be a sane number of kilograms", async () => {
  await assertFails(
    setDoc(doc(mine(), FITNESS), { ...goodProfile, targetWeightKg: 5 })
  );
  await assertFails(
    setDoc(doc(mine(), FITNESS), { ...goodProfile, targetWeightKg: "80" })
  );
  await assertSucceeds(
    setDoc(doc(mine(), FITNESS), { ...goodProfile, targetWeightKg: 80.5 })
  );
});

test("an update is validated too", async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), FITNESS), goodProfile)
  );
  await assertSucceeds(
    updateDoc(doc(mine(), FITNESS), { primaryGoal: "loseFat" })
  );
  await assertFails(
    updateDoc(doc(mine(), FITNESS), { primaryGoal: "flyToTheMoon" })
  );
});

test("the owner can delete their fitness profile", async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), FITNESS), goodProfile)
  );
  await assertSucceeds(deleteDoc(doc(mine(), FITNESS)));
});

test("the other private documents still take any shape", async () => {
  await assertSucceeds(
    setDoc(doc(mine(), `users/${ME}/private/body`), {
      heightCm: 180,
      weightKg: 80,
      units: "metric",
    })
  );
});

// ---- weeklyGoalDays on users/{uid} ----

test("the profile can be created with weeklyGoalDays", async () => {
  await assertSucceeds(createProfile(mine(), { weeklyGoalDays: 4 }));
});

test("the profile can be created without weeklyGoalDays", async () => {
  await assertSucceeds(createProfile(mine()));
});

test("weeklyGoalDays outside 1-7 is refused", async () => {
  for (const days of [0, 8, 4.5, "4"]) {
    await env.clearFirestore();
    await assertFails(createProfile(mine(), { weeklyGoalDays: days }));
  }
});

test("weeklyGoalDays can be changed later, within range", async () => {
  await createProfile(mine(), { weeklyGoalDays: 4 });
  // 1 and 7 come from the progress tab's own setter, not sign-up.
  for (const days of [1, 7]) {
    await assertSucceeds(
      updateDoc(doc(mine(), `users/${ME}`), { weeklyGoalDays: days })
    );
  }
  await assertFails(
    updateDoc(doc(mine(), `users/${ME}`), { weeklyGoalDays: 0 })
  );
});

// ---- weighIns ----

const WEIGH_IN = `users/${ME}/weighIns/2026-10-09`;

test("the owner can log a weigh-in", async () => {
  await assertSucceeds(
    setDoc(doc(mine(), WEIGH_IN), {
      weightKg: 82.4,
      recordedAt: serverTimestamp(),
    })
  );
});

test("weigh-ins are private to their owner", async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), WEIGH_IN), { weightKg: 82.4 })
  );
  await assertSucceeds(getDoc(doc(mine(), WEIGH_IN)));
  await assertFails(getDoc(doc(theirs(), WEIGH_IN)));
  await assertFails(
    setDoc(doc(theirs(), WEIGH_IN), {
      weightKg: 60,
      recordedAt: serverTimestamp(),
    })
  );
});

test("a weigh-in needs a day-key id, sane kilograms and a server time", async () => {
  await assertFails(
    setDoc(doc(mine(), `users/${ME}/weighIns/today`), {
      weightKg: 82.4,
      recordedAt: serverTimestamp(),
    })
  );
  await assertFails(
    setDoc(doc(mine(), WEIGH_IN), {
      weightKg: 2000,
      recordedAt: serverTimestamp(),
    })
  );
  await assertFails(
    setDoc(doc(mine(), WEIGH_IN), {
      weightKg: 82.4,
      recordedAt: new Date("2020-01-01"),
    })
  );
  await assertFails(
    setDoc(doc(mine(), WEIGH_IN), {
      weightKg: 82.4,
      recordedAt: serverTimestamp(),
      note: "after lunch",
    })
  );
});

test("the owner can delete a weigh-in", async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), WEIGH_IN), { weightKg: 82.4 })
  );
  await assertSucceeds(deleteDoc(doc(mine(), WEIGH_IN)));
});
