import crypto from "node:crypto";

import jwt from "jsonwebtoken";

import { config } from "./config.js";

export function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString("hex");
  const digest = crypto.pbkdf2Sync(password, salt, 120000, 32, "sha256").toString("hex");
  return `${salt}$${digest}`;
}

export function verifyPassword(password, stored) {
  const [salt, digest] = String(stored).split("$");
  if (!salt || !digest) {
    return false;
  }
  const candidate = crypto.pbkdf2Sync(password, salt, 120000, 32, "sha256").toString("hex");
  const left = Buffer.from(candidate, "hex");
  const right = Buffer.from(digest, "hex");
  if (left.length !== right.length) {
    return false;
  }
  return crypto.timingSafeEqual(left, right);
}

export function createAccessToken(userId) {
  return jwt.sign({ sub: String(userId) }, config.secretKey, {
    expiresIn: `${config.tokenExpireMinutes}m`,
  });
}

export function readAccessToken(token) {
  const payload = jwt.verify(token, config.secretKey);
  return Number(payload.sub);
}

export function publicUser(user) {
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    created_at: user.created_at,
  };
}
