import { ROLE_LABELS, permissionsFor } from "./roles.js";
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

/** Response body for any successful sign-in. */
export async function sessionResponse(db, user, extra = {}) {
  return {
    access_token: createAccessToken(user.id),
    token_type: "bearer",
    user: publicUser(user),
    memberships: await membershipsFor(db, user.id),
    ...extra,
  };
}
