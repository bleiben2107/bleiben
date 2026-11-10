import dns from "node:dns";
import fs from "node:fs";
import path from "node:path";

import { MongoClient } from "mongodb";

import { config } from "./config.js";

function emptyStore() {
  return {
    users: [],
    stays: [],
    nextUserId: 1,
    nextStayId: 1,
  };
}

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

  return {
    kind: "json",
    async ping() {
      return true;
    },
    async close() {},
    findUserByEmail(email) {
      return data.users.find((user) => user.email === email.toLowerCase().trim()) ?? null;
    },
    findUserById(id) {
      return data.users.find((user) => user.id === id) ?? null;
    },
    createUser({ name, email, passwordHash }) {
      const user = {
        id: data.nextUserId++,
        name: name.trim(),
        email: email.toLowerCase().trim(),
        password_hash: passwordHash,
        created_at: new Date().toISOString(),
      };
      data.users.push(user);
      persist();
      return user;
    },
    listStays(userId) {
      return data.stays
        .filter((stay) => stay.user_id === userId)
        .sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
    },
    findStay(id, userId) {
      return data.stays.find((stay) => stay.id === id && stay.user_id === userId) ?? null;
    },
    createStay(userId, payload) {
      const now = new Date().toISOString();
      const stay = {
        id: data.nextStayId++,
        user_id: userId,
        title: payload.title,
        location: payload.location,
        notes: payload.notes ?? "",
        check_in: payload.check_in ?? null,
        check_out: payload.check_out ?? null,
        created_at: now,
        updated_at: now,
      };
      data.stays.push(stay);
      persist();
      return stay;
    },
    updateStay(stay, payload) {
      Object.assign(stay, {
        title: payload.title ?? stay.title,
        location: payload.location ?? stay.location,
        notes: payload.notes ?? stay.notes,
        check_in: payload.check_in === undefined ? stay.check_in : payload.check_in,
        check_out: payload.check_out === undefined ? stay.check_out : payload.check_out,
        updated_at: new Date().toISOString(),
      });
      persist();
      return stay;
    },
    deleteStay(id, userId) {
      const index = data.stays.findIndex((stay) => stay.id === id && stay.user_id === userId);
      if (index === -1) {
        return false;
      }
      data.stays.splice(index, 1);
      persist();
      return true;
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
  const stays = db.collection("stays");
  const counters = db.collection("counters");

  await Promise.all([
    users.createIndex({ email: 1 }, { unique: true }),
    users.createIndex({ id: 1 }, { unique: true }),
    stays.createIndex({ user_id: 1, id: 1 }),
    stays.createIndex({ id: 1 }, { unique: true }),
  ]);

  async function nextSequence(name) {
    const result = await counters.findOneAndUpdate(
      { _id: name },
      { $inc: { seq: 1 } },
      { upsert: true, returnDocument: "after" },
    );
    return result.seq;
  }

  return {
    kind: "mongodb",
    dbName,
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
    async createUser({ name, email, passwordHash }) {
      const id = await nextSequence("users");
      const user = {
        id,
        name: name.trim(),
        email: email.toLowerCase().trim(),
        password_hash: passwordHash,
        created_at: new Date().toISOString(),
      };
      await users.insertOne({ ...user });
      return user;
    },
    async listStays(userId) {
      return stays
        .find({ user_id: userId }, { projection: { _id: 0 } })
        .sort({ created_at: -1 })
        .toArray();
    },
    async findStay(id, userId) {
      if (!Number.isInteger(id)) {
        return null;
      }
      return stays.findOne({ id, user_id: userId }, { projection: { _id: 0 } });
    },
    async createStay(userId, payload) {
      const id = await nextSequence("stays");
      const now = new Date().toISOString();
      const stay = {
        id,
        user_id: userId,
        title: payload.title,
        location: payload.location,
        notes: payload.notes ?? "",
        check_in: payload.check_in ?? null,
        check_out: payload.check_out ?? null,
        created_at: now,
        updated_at: now,
      };
      await stays.insertOne({ ...stay });
      return stay;
    },
    async updateStay(stay, payload) {
      const updates = {
        title: payload.title ?? stay.title,
        location: payload.location ?? stay.location,
        notes: payload.notes ?? stay.notes,
        check_in: payload.check_in === undefined ? stay.check_in : payload.check_in,
        check_out: payload.check_out === undefined ? stay.check_out : payload.check_out,
        updated_at: new Date().toISOString(),
      };
      return stays.findOneAndUpdate(
        { id: stay.id, user_id: stay.user_id },
        { $set: updates },
        { returnDocument: "after", projection: { _id: 0 } },
      );
    },
    async deleteStay(id, userId) {
      if (!Number.isInteger(id)) {
        return false;
      }
      const result = await stays.deleteOne({ id, user_id: userId });
      return result.deletedCount > 0;
    },
  };
}
