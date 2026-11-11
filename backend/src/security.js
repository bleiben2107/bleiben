import jwt from "jsonwebtoken";

import { config } from "./config.js";

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
