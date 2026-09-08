/**
 * A small in-memory stand-in for firebase-admin.
 *
 * It exists because the Firestore emulator will not start on every machine
 * this project is developed on, and a deletion sweep is the last thing that
 * should go untested for want of a local emulator. What it verifies is this
 * module's own logic — which collections are swept, which fields are matched,
 * which way the counters move. It does not verify Firestore's semantics, and a
 * green run here is not a substitute for exercising the real thing once before
 * the function is trusted with a real account.
 *
 * Documents are held in one flat Map keyed by path, which is what makes both
 * collection-group queries and recursive deletes a prefix test.
 */

class FieldValueSentinel {
  constructor(op, value) {
    this.op = op;
    this.value = value;
  }
}

const FieldValue = {
  increment: (n) => new FieldValueSentinel("increment", n),
  arrayRemove: (...values) => new FieldValueSentinel("arrayRemove", values),
  delete: () => new FieldValueSentinel("delete"),
  serverTimestamp: () => new FieldValueSentinel("serverTimestamp"),
};

/** `a/b/c/d` → `a/b`; a document's parent collection is `a/b/c`. */
function parentDocPath(docPath) {
  const parts = docPath.split("/");
  if (parts.length <= 2) return null;
  return parts.slice(0, parts.length - 2).join("/");
}

function collectionIdOf(docPath) {
  const parts = docPath.split("/");
  return parts[parts.length - 2];
}

function matches(data, [field, op, value]) {
  // Dotted paths are not used by any filter in the deletion sweep, so a plain
  // property read is enough and a dotted one would be silently wrong.
  const actual = data[field];
  switch (op) {
    case "==":
      return actual === value;
    case "array-contains":
      return Array.isArray(actual) && actual.includes(value);
    // The running-challenge engine filters membership by a set of statuses and
    // buckets attributions by day key, so `in` and the range operators are
    // exercised here even though the deletion sweep never needed them.
    case "in":
      return Array.isArray(value) && value.includes(actual);
    case ">=":
      return actual !== undefined && actual >= value;
    case ">":
      return actual !== undefined && actual > value;
    case "<=":
      return actual !== undefined && actual <= value;
    case "<":
      return actual !== undefined && actual < value;
    default:
      throw new Error(`fake_admin: unsupported operator ${op}`);
  }
}

function applyWrite(store, path, updates, { merge }) {
  const existing = store.get(path);
  const base = merge && existing ? { ...existing } : {};

  for (const [key, raw] of Object.entries(updates)) {
    // Dotted keys are tested BEFORE sentinels, and the order is the whole
    // point: `reactionCounts.fire: increment(-1)` addresses a field inside a
    // map, and resolving the sentinel first would write a literal key called
    // "reactionCounts.fire" and leave the real counter untouched — which is
    // exactly the bug a fake is supposed to catch rather than introduce.
    if (key.includes(".")) {
      const [head, ...rest] = key.split(".");
      const tail = rest.join(".");
      const map = { ...(base[head] ?? {}) };
      if (raw instanceof FieldValueSentinel) {
        switch (raw.op) {
          case "delete":
            delete map[tail];
            break;
          case "increment":
            map[tail] = (map[tail] ?? 0) + raw.value;
            break;
          default:
            throw new Error(`fake_admin: unsupported nested sentinel ${raw.op}`);
        }
      } else {
        map[tail] = raw;
      }
      base[head] = map;
      continue;
    }

    if (raw instanceof FieldValueSentinel) {
      switch (raw.op) {
        case "increment":
          base[key] = (base[key] ?? 0) + raw.value;
          break;
        case "arrayRemove":
          base[key] = (base[key] ?? []).filter((v) => !raw.value.includes(v));
          break;
        case "delete":
          delete base[key];
          break;
        case "serverTimestamp":
          base[key] = new Date(0);
          break;
        default:
          throw new Error(`fake_admin: unsupported sentinel ${raw.op}`);
      }
      continue;
    }

    base[key] = raw;
  }

  store.set(path, base);
}

/**
 * Nested sentinels inside a dotted key are resolved above; this handles the
 * plain-object case update() is given.
 */
function normaliseUpdate(store, path, updates) {
  const existing = store.get(path);
  if (!existing) return; // update() on a missing doc is a no-op here.
  applyWrite(store, path, updates, { merge: true });
}

class FakeQuery {
  constructor(store, { collectionId, prefix, group }, filters = [], cap = null) {
    this._store = store;
    this._scope = { collectionId, prefix, group };
    this._filters = filters;
    this._cap = cap;
  }

  where(field, op, value) {
    return new FakeQuery(
      this._store,
      this._scope,
      [...this._filters, [field, op, value]],
      this._cap
    );
  }

  limit(n) {
    return new FakeQuery(this._store, this._scope, this._filters, n);
  }

  /**
   * Ordering is accepted and ignored.
   *
   * Every caller under test either sorts the result itself or reads it
   * order-insensitively, so honouring this would test nothing. It is accepted
   * rather than thrown on so that a query written the way the real one is stays
   * runnable here.
   */
  orderBy() {
    return this;
  }

  count() {
    const query = this;
    return {
      async get() {
        const snapshot = await query.get();
        return { data: () => ({ count: snapshot.size }) };
      },
    };
  }

  async get() {
    const hits = [];
    for (const [path, data] of this._store) {
      if (this._scope.group) {
        if (collectionIdOf(path) !== this._scope.collectionId) continue;
      } else if (
        !path.startsWith(this._scope.prefix) ||
        path.slice(this._scope.prefix.length).includes("/")
      ) {
        continue;
      }
      if (!this._filters.every((f) => matches(data, f))) continue;
      hits.push(makeSnapshot(this._store, path, data));
      if (this._cap != null && hits.length >= this._cap) break;
    }
    return { empty: hits.length === 0, size: hits.length, docs: hits };
  }
}

function makeSnapshot(store, path, data) {
  return {
    id: path.split("/").pop(),
    ref: makeDocRef(store, path),
    exists: true,
    data: () => data,
    // Field access, as the real DocumentSnapshot offers it. Dotted paths are
    // not supported for the same reason `matches` does not support them: no
    // caller under test uses one, and a plain property read on "a.b" would be
    // silently wrong rather than loudly unsupported.
    get: (field) => data[field],
  };
}

function makeDocRef(store, path) {
  const parentDoc = parentDocPath(path);
  return {
    path,
    id: path.split("/").pop(),
    parent: {
      id: collectionIdOf(path),
      parent: parentDoc ? makeDocRef(store, parentDoc) : null,
    },
    collection(name) {
      return new FakeCollection(store, `${path}/${name}`);
    },
    async delete() {
      store.delete(path);
    },
    async get() {
      const data = store.get(path);
      return data
        ? makeSnapshot(store, path, data)
        : {
            exists: false,
            id: this.id,
            ref: this,
            data: () => undefined,
            get: () => undefined,
          };
    },
    async set(updates, options = {}) {
      applyWrite(store, path, updates, { merge: options.merge === true });
    },
    /**
     * Throws on a missing document, exactly as the real SDK does — which is
     * the property the counter corrections depend on to avoid resurrecting
     * documents somebody else already deleted.
     */
    async update(updates) {
      if (!store.has(path)) {
        const error = new Error(`no document to update: ${path}`);
        error.code = 5; // NOT_FOUND
        throw error;
      }
      applyWrite(store, path, updates, { merge: true });
    },
  };
}

class FakeCollection extends FakeQuery {
  constructor(store, prefix) {
    super(store, {
      collectionId: prefix.split("/").pop(),
      prefix: `${prefix}/`,
      group: false,
    });
    this._prefix = prefix;
  }

  doc(id) {
    return makeDocRef(this._store, `${this._prefix}/${id}`);
  }

  /**
   * Auto-id create. The ids are sequential rather than random so a test can
   * assert on a path, which a real auto-id would make impossible.
   */
  async add(data) {
    const id = `auto_${++FakeCollection._autoId}`;
    const ref = this.doc(id);
    await ref.set(data);
    return ref;
  }
}

FakeCollection._autoId = 0;

class FakeBatch {
  constructor(store) {
    this._store = store;
    this._ops = [];
  }

  set(ref, updates, options = {}) {
    this._ops.push(() =>
      applyWrite(this._store, ref.path, updates, {
        merge: options.merge === true,
      })
    );
  }

  update(ref, updates) {
    this._ops.push(() => normaliseUpdate(this._store, ref.path, updates));
  }

  delete(ref) {
    this._ops.push(() => this._store.delete(ref.path));
  }

  async commit() {
    for (const op of this._ops) op();
    this._ops = [];
  }
}

class FakeFirestore {
  constructor(store) {
    this._store = store;
  }

  collection(name) {
    return new FakeCollection(this._store, name);
  }

  collectionGroup(name) {
    return new FakeQuery(this._store, {
      collectionId: name,
      prefix: null,
      group: true,
    });
  }

  batch() {
    return new FakeBatch(this._store);
  }

  async recursiveDelete(ref) {
    this._store.delete(ref.path);
    for (const path of [...this._store.keys()]) {
      if (path.startsWith(`${ref.path}/`)) this._store.delete(path);
    }
  }
}

/**
 * Builds a fake `firebase-admin` around [seed], a plain object of
 * `path -> document data`.
 *
 * Returns the module stub plus the live store, so a test can assert on what
 * survived by path.
 */
function createFakeAdmin(seed = {}) {
  const store = new Map(Object.entries(seed).map(([k, v]) => [k, { ...v }]));
  const firestoreInstance = new FakeFirestore(store);
  const deletedUsers = [];
  const storageFiles = new Map();

  // Cloud Messaging. Records what was sent, and lets a test declare one token
  // dead so the pruning path in push.js can be exercised without FCM.
  const sentMessages = [];
  const tokenFailures = new Map();

  const messaging = () => ({
    async sendEachForMulticast(message) {
      sentMessages.push(message);
      const responses = (message.tokens ?? []).map((token) => {
        const code = tokenFailures.get(token);
        return code
          ? { success: false, error: { code } }
          : { success: true, messageId: `msg_${token}` };
      });
      return {
        responses,
        successCount: responses.filter((r) => r.success).length,
        failureCount: responses.filter((r) => !r.success).length,
      };
    },
  });

  const firestore = () => firestoreInstance;
  firestore.FieldValue = FieldValue;

  // Timestamps are plain Dates here. The range filters in `matches` compare
  // with `>=` / `<`, which coerce a Date through valueOf, so a seeded Date and
  // a bound built by fromDate order correctly against each other without a
  // wrapper type. Anything that needs real Timestamp semantics -- toDate,
  // nanosecond precision -- is not exercised by these tests.
  firestore.Timestamp = {
    fromDate: (date) => date,
    fromMillis: (millis) => new Date(millis),
    now: () => new Date(),
  };

  const admin = {
    // A default app already exists, which is what the modules under test check
    // for. `apps` is carried alongside it only so that anything still counting
    // is visibly answered the same way the real SDK would answer it -- see
    // ensureDefaultApp in challenges.js for why counting is the wrong question.
    app: () => ({ name: "[DEFAULT]" }),
    apps: [{ name: "[DEFAULT]" }],
    initializeApp: () => {},
    firestore,
    auth: () => ({
      deleteUser: async (uid) => {
        deletedUsers.push(uid);
      },
    }),
    messaging,
    storage: () => ({
      bucket: () => ({
        getFiles: async ({ prefix }) => [
          [...storageFiles.keys()]
            .filter((name) => name.startsWith(prefix))
            .map((name) => ({
              name,
              delete: async () => storageFiles.delete(name),
            })),
        ],
      }),
    }),
  };

  return {
    admin,
    store,
    deletedUsers,
    storageFiles,
    sentMessages,
    tokenFailures,
  };
}

module.exports = { createFakeAdmin, FieldValue };
