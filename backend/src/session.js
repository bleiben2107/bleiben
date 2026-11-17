import { ROLE_LABELS, permissionsFor } from "./roles.js";
import crypto from "node:crypto";

import { config } from "./config.js";
import { createAccessToken, publicUser } from "./security.js";

/** The user's active memberships with their organisation and role. */
export async function membershipsFor(db, userId) {
  const memberships = await db.findDocs("memberships", { user_id: userId, status: "active" });
  const result = [];
  for (const m of memberships) {
    const org = await db.findDoc("organizations", { id: m.org_id });
    if (!org) continue;
    result.push({
      membership_id: m.id,
      org_id: org.id,
      org_name: org.name,
      role: m.role,
      role_label: ROLE_LABELS[m.role],
      permissions: permissionsFor(m.role),
    });
  }
  return result;
}

/** Describes the device from its User-Agent ("Chrome on Windows"). */
export function deviceLabel(ua = "") {
  const browser = /Edg\//.test(ua) ? "Edge" : /OPR\//.test(ua) ? "Opera" : /Chrome\//.test(ua) ? "Chrome" : /Firefox\//.test(ua) ? "Firefox" : /Safari\//.test(ua) ? "Safari" : /Dart|okhttp|CFNetwork/i.test(ua) ? "Bleiben app" : "Browser";
  const os = /Windows/.test(ua) ? "Windows" : /Android/.test(ua) ? "Android" : /iPhone|iPad|iOS/.test(ua) ? "iOS" : /Mac OS X/.test(ua) ? "macOS" : /Linux/.test(ua) ? "Linux" : "";
  return os ? `${browser} on ${os}` : browser;
}

/** Response body for any successful sign-in. Records the session (Settings → Security). */
export async function sessionResponse(db, user, extra = {}, req = null) {
  const sid = crypto.randomBytes(16).toString("hex");
  const now = new Date().toISOString();
  const ua = String(req?.headers?.["user-agent"] ?? "").slice(0, 300);
  await db.insertDoc("sessions", {
    sid,
    user_id: user.id,
    device: deviceLabel(ua),
    user_agent: ua,
    ip: req?.ip ?? null,
    method: extra?.is_new_user ? "signup" : "login",
    created_at: now,
    last_seen_at: now,
    expires_at: new Date(Date.now() + config.tokenExpireMinutes * 60000).toISOString(),
    revoked_at: null,
  });
  return {
    access_token: createAccessToken(user.id, sid),
    token_type: "bearer",
    user: publicUser(user),
    memberships: await membershipsFor(db, user.id),
    ...extra,
  };
}
