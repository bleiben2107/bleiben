import { can } from "../roles.js";
import { readAccessSession } from "../security.js";

export function requireUser(db) {
  return async (req, res, next) => {
    const header = req.headers.authorization || "";
    const [scheme, token] = header.split(" ");
    if (scheme !== "Bearer" || !token) {
      return res.status(401).json({ detail: "Not authenticated" });
    }
    let userId;
    let sid;
    try {
      ({ userId, sid } = readAccessSession(token));
    } catch {
      return res.status(401).json({ detail: "Invalid token" });
    }
    try {
      const user = await db.findUserById(userId);
      if (!user) {
        return res.status(401).json({ detail: "User not found" });
      }
      if (sid) {
        const session = await db.findDoc("sessions", { sid });
        if (!session || session.user_id !== userId || session.revoked_at) {
          return res.status(401).json({ detail: "You were signed out of this device" });
        }
        // Throttled "last active" update.
        if (Date.now() - Date.parse(session.last_seen_at) > 5 * 60000) {
          await db.updateDoc("sessions", { id: session.id }, { last_seen_at: new Date().toISOString(), ip: req.ip ?? session.ip });
        }
        req.sessionId = sid;
      }
      req.user = user;
      return next();
    } catch (err) {
      return next(err);
    }
  };
}

/**
 * Loads the organisation from `:orgId` and the caller's active membership,
 * then checks `permission`. Sets `req.org` and `req.membership`.
 */
export function requireOrgPermission(db, permission) {
  return async (req, res, next) => {
    try {
      const orgId = Number(req.params.orgId);
      const org = Number.isInteger(orgId) ? await db.findDoc("organizations", { id: orgId }) : null;
      const membership = org
        ? await db.findDoc("memberships", { org_id: org.id, user_id: req.user.id, status: "active" })
        : null;
      if (!org || !membership) {
        return res.status(404).json({ detail: "Organisation not found" });
      }
      if (!can(membership.role, permission)) {
        return res.status(403).json({ detail: "Your role doesn't allow this", required: permission });
      }
      req.org = org;
      req.membership = membership;
      return next();
    } catch (err) {
      return next(err);
    }
  };
}

/**
 * Org scope for module routes (properties, calendar, bookings…), taken from
 * the `X-Org-Id` header: GET/HEAD need `read`, other methods `write`.
 * Without the header the request is personal (`req.scope.user_id`).
 */
export function orgScope(db, { read, write }) {
  return async (req, res, next) => {
    const raw = req.headers["x-org-id"];
    if (!raw) {
      req.scope = { user_id: req.user.id, org_id: null };
      return next();
    }
    try {
      const orgId = Number(raw);
      const membership = Number.isInteger(orgId)
        ? await db.findDoc("memberships", { org_id: orgId, user_id: req.user.id, status: "active" })
        : null;
      if (!membership) {
        return res.status(404).json({ detail: "Organisation not found" });
      }
      const needed = ["GET", "HEAD"].includes(req.method) ? read : write;
      if (!can(membership.role, needed)) {
        return res.status(403).json({ detail: "Your role is read-only here", required: needed });
      }
      req.scope = { org_id: orgId };
      req.membership = membership;
      return next();
    } catch (err) {
      return next(err);
    }
  };
}
