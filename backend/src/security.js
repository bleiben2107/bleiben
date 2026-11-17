import jwt from "jsonwebtoken";

import { config } from "./config.js";

/** `sid` links the token to a stored session so it can be signed out. */
export function createAccessToken(userId, sid = null) {
  return jwt.sign(sid ? { sub: String(userId), sid } : { sub: String(userId) }, config.secretKey, {
    expiresIn: `${config.tokenExpireMinutes}m`,
  });
}

export function readAccessToken(token) {
  const payload = jwt.verify(token, config.secretKey);
  return Number(payload.sub);
}

export function readAccessSession(token) {
  const payload = jwt.verify(token, config.secretKey);
  return { userId: Number(payload.sub), sid: payload.sid ?? null };
}

export function publicUser(user) {
  return {
    id: user.id,
    name: user.name ?? "",
    email: user.email ?? null,
    phone: user.phone ?? null,
    email_verified: Boolean(user.email_verified),
    phone_verified: Boolean(user.phone_verified),
    avatar_url: user.avatar_url ?? null,
    profile: user.profile ?? {},
    created_at: user.created_at,
  };
}
