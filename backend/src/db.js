import dns from "node:dns";
import fs from "node:fs";
import path from "node:path";

import { MongoClient } from "mongodb";

import { config } from "./config.js";

function emptyStore() {
  return {
    users: [],
    nextUserId: 1,
    counters: {},
  };
}

/** Every key in `match` must equal the document's value; null matches missing. */
export function matchesDoc(doc, match = {}) {
  return Object.entries(match).every(([key, value]) =>
    value === null ? doc[key] == null : doc[key] === value,
  );
}

const clone = (value) => (value == null ? value : structuredClone(value));

export function createDb(filePath = config.dataFile) {
  const resolved = path.resolve(filePath);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });

  let data = emptyStore();
  if (fs.existsSync(resolved)) {
    data = { ...emptyStore(), ...JSON.parse(fs.readFileSync(resolved, "utf8")) };
  } else {
    persist();
  }

  function persist() {
    fs.writeFileSync(resolved, JSON.stringify(data, null, 2));
  }

  function nextId(collection) {
    if (collection === "users") return data.nextUserId++;
    data.counters[collection] = (data.counters[collection] ?? 0) + 1;
    return data.counters[collection];
  }

  function rows(collection) {
    data[collection] ??= [];
    return data[collection];
  }

  return {
    kind: "json",
    async ping() {
      return true;
    },
    async close() {},

    // ── Generic documents ──────────────────────────────────────────────────
    async insertDoc(collection, doc) {
      const row = { id: nextId(collection), ...doc };
      rows(collection).push(row);
      persist();
      return clone(row);
    },
    async findDoc(collection, match) {
      return clone(rows(collection).find((row) => matchesDoc(row, match)) ?? null);
    },
    async findDocs(collection, match) {
      return clone(rows(collection).filter((row) => matchesDoc(row, match)));
    },
    async updateDoc(collection, match, set) {
      const row = rows(collection).find((r) => matchesDoc(r, match));
      if (!row) return null;
      Object.assign(row, set);
      persist();
      return clone(row);
    },
    async deleteDocs(collection, match) {
      const list = rows(collection);
      const before = list.length;
      data[collection] = list.filter((row) => !matchesDoc(row, match));
      persist();
      return before - data[collection].length;
    },

    findUserByEmail(email) {
      return data.users.find((user) => user.email === email.toLowerCase().trim()) ?? null;
    },
    findUserById(id) {
      return data.users.find((user) => user.id === id) ?? null;
    },
  };
}

export async function createMongoDb(uri = config.mongodbUri, dbName = config.mongodbDb) {
  if (!uri) {
    throw new Error("MONGODB_URI is not configured");
  }
  if (
    uri.startsWith("mongodb+srv://") &&
    dns.getServers().every((server) => server === "127.0.0.1" || server === "::1")
  ) {
    dns.setServers(["1.1.1.1", "8.8.8.8"]);
  }

  const client = new MongoClient(uri, { serverSelectionTimeoutMS: 5000 });
  await client.connect();
  const db = client.db(dbName);
  await db.command({ ping: 1 });

  const users = db.collection("users");
  const counters = db.collection("counters");

  const indexResults = await Promise.allSettled([
    users.createIndex(
      { email: 1 },
      { unique: true, partialFilterExpression: { email: { $type: "string" } } },
    ),
    users.createIndex({ phone: 1 }, { partialFilterExpression: { phone: { $type: "string" } } }),
    db.collection("otp_challenges").createIndex({ target: 1, channel: 1 }),
    db.collection("memberships").createIndex({ org_id: 1, user_id: 1 }),
    db.collection("organizations").createIndex({ id: 1 }, { unique: true }),
    users.createIndex({ id: 1 }, { unique: true }),
  ]);
  for (const r of indexResults) {
    if (r.status === "rejected") {
      // e.g. an older strict unique `email_1` index: phone-only users need the
      // partial index. Drop `email_1` once so it can be recreated.
      console.warn(`[MongoDB] Index setup: ${r.reason?.message ?? r.reason}`);
    }
  }

  async function nextSequence(name) {
    const result = await counters.findOneAndUpdate(
      { _id: name },
      { $inc: { seq: 1 } },
      { upsert: true, returnDocument: "after" },
    );
    return result.seq;
  }

  // Mongo cannot express "null matches missing" with plain equality the same
  // way; translate null to {$in: [null]} which matches null and absent fields.
  const toQuery = (match = {}) =>
    Object.fromEntries(
      Object.entries(match).map(([k, v]) => [k, v === null ? { $in: [null] } : v]),
    );

  return {
    kind: "mongodb",
    dbName,

    // ── Generic documents ──────────────────────────────────────────────────
    async insertDoc(collection, doc) {
      const row = { id: await nextSequence(collection), ...doc };
      await db.collection(collection).insertOne({ ...row });
      return row;
    },
    async findDoc(collection, match) {
      return db.collection(collection).findOne(toQuery(match), { projection: { _id: 0 } });
    },
    async findDocs(collection, match) {
      return db
        .collection(collection)
        .find(toQuery(match), { projection: { _id: 0 } })
        .toArray();
    },
    async updateDoc(collection, match, set) {
      return db
        .collection(collection)
        .findOneAndUpdate(
          toQuery(match),
          { $set: set },
          { returnDocument: "after", projection: { _id: 0 } },
        );
    },
    async deleteDocs(collection, match) {
      const result = await db.collection(collection).deleteMany(toQuery(match));
      return result.deletedCount;
    },
    async ping() {
      await db.command({ ping: 1 });
      return true;
    },
    async close() {
      await client.close();
    },
    async findUserByEmail(email) {
      return users.findOne({ email: email.toLowerCase().trim() }, { projection: { _id: 0 } });
    },
    async findUserById(id) {
      if (!Number.isInteger(id)) {
        return null;
      }
      return users.findOne({ id }, { projection: { _id: 0 } });
    },
  };
}
