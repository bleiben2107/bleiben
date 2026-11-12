/**
 * Organisation roles and what each may do. Modules add their own
 * permissions here (e.g. "properties.read" / "properties.write"). Checked on the server for every
 * org-scoped request; the client only uses them to hide controls.
 */
export const ROLES = ["owner", "manager", "staff", "read_only"];

export const ROLE_LABELS = {
  owner: "Owner",
  manager: "Manager",
  staff: "Staff",
  read_only: "Read-only",
};

export const PERMISSIONS = {
  owner: [
    "org.read",
    "org.update",
    "org.delete",
    "billing.manage",
    "team.read",
    "team.manage",
    "team.assign_owner",
    "properties.read",
    "properties.write",
    "properties.publish",
    "properties.delete",
  ],
  manager: [
    "org.read",
    "org.update",
    "team.read",
    "team.manage",
    "properties.read",
    "properties.write",
    "properties.publish",
  ],
  staff: ["org.read", "team.read", "properties.read", "properties.write"],
  read_only: ["org.read", "team.read", "properties.read"],
};

export function isRole(value) {
  return ROLES.includes(value);
}

export function can(role, permission) {
  return Boolean(PERMISSIONS[role]?.includes(permission));
}

/** Whether `actorRole` may grant (or change someone from/to) `targetRole`. */
export function canAssign(actorRole, targetRole) {
  if (!can(actorRole, "team.manage")) {
    return false;
  }
  return targetRole !== "owner" || can(actorRole, "team.assign_owner");
}

export function permissionsFor(role) {
  return [...(PERMISSIONS[role] ?? [])];
}
