import fs from "node:fs";
import path from "node:path";

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
