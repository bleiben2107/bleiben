import { Router } from "express";

import { config } from "../config.js";
import { inviteEmail } from "../messaging.js";
import { requireOrgPermission } from "../middleware/auth.js";
import { ROLE_LABELS, canAssign, isRole, permissionsFor } from "../roles.js";
import { publicUser } from "../security.js";
import { membershipsFor } from "../session.js";
import { generateToken, hashSecret, normalizeEmail } from "../tokens.js";

const nowIso = () => new Date().toISOString();

function publicOrg(org, membership) {
  return {
    id: org.id,
    name: org.name,
    created_at: org.created_at,
    role: membership?.role ?? null,
    role_label: membership ? ROLE_LABELS[membership.role] : null,
    permissions: membership ? permissionsFor(membership.role) : [],
  };
}

/**
 * Creates an organisation with `user` as Owner (PRD AUTH-3: the tenant is
 * provisioned automatically on first launch).
 */
export async function provisionOrganization(db, user, name) {
  const org = await db.insertDoc("organizations", {
    name,
    created_by: user.id,
    created_at: nowIso(),
  });
  const membership = await db.insertDoc("memberships", {
    org_id: org.id,
    user_id: user.id,
    role: "owner",
    status: "active",
    created_at: nowIso(),
  });
  return { org, membership };
}

/**
 * Creates (or refreshes) a pending invite and emails it. Returns the invite
 * plus, outside production without SMTP, the link for local testing.
 */
async function createInvite(db, mailer, { org, inviter, email, role }) {
  const existingUser = await db.findUserByEmail(email);
  if (existingUser) {
    const member = await db.findDoc("memberships", { org_id: org.id, user_id: existingUser.id, status: "active" });
    if (member) {
      return { error: `${email} is already a member`, status: 409 };
    }
  }
  const active = await db.findDocs("memberships", { org_id: org.id, status: "invited" });
  if (active.length >= 50) {
    return { error: "Too many pending invites", status: 429 };
  }
  await db.deleteDocs("memberships", { org_id: org.id, invited_email: email, status: "invited" });

  const token = generateToken();
  const invite = await db.insertDoc("memberships", {
    org_id: org.id,
    user_id: null,
    role,
    status: "invited",
    invited_email: email,
    invited_by: inviter.id,
    invite_token_hash: hashSecret(token),
    expires_at: new Date(Date.now() + config.inviteTtlDays * 86400 * 1000).toISOString(),
    created_at: nowIso(),
  });
  const url = `${config.appBaseUrl}/?invite_token=${encodeURIComponent(token)}`;
  await mailer.send({
    to: email,
    ...inviteEmail({
      url,
      orgName: org.name,
      inviterName: inviter.name,
      role: ROLE_LABELS[role],
      days: config.inviteTtlDays,
    }),
  });
  return { invite, devLink: !mailer.configured && !config.isProduction ? url : undefined };
}

async function publicMember(db, m) {
  const user = m.user_id ? await db.findUserById(m.user_id) : null;
  return {
    id: m.id,
    role: m.role,
    role_label: ROLE_LABELS[m.role],
    status: m.status,
    user: user ? publicUser(user) : null,
    invited_email: m.invited_email ?? null,
    expires_at: m.status === "invited" ? m.expires_at : null,
    expired: m.status === "invited" && Date.parse(m.expires_at) < Date.now(),
    created_at: m.created_at,
  };
}

export function orgsRouter(db, { mailer }) {
  const router = Router();

  // ── Organisations ─────────────────────────────────────────────────────────

  router.get("/", async (req, res, next) => {
    try {
      return res.json(await membershipsFor(db, req.user.id));
    } catch (err) {
      return next(err);
    }
  });

  router.post("/", async (req, res, next) => {
    try {
      const name = String(req.body?.name || "").trim().slice(0, 100);
      if (name.length < 2) {
        return res.status(400).json({ detail: "Organisation name must be at least 2 characters" });
      }
      const { org, membership } = await provisionOrganization(db, req.user, name);
      return res.status(201).json(publicOrg(org, membership));
    } catch (err) {
      return next(err);
    }
  });

  router.get("/:orgId", requireOrgPermission(db, "org.read"), (req, res) =>
    res.json(publicOrg(req.org, req.membership)),
  );

  router.patch("/:orgId", requireOrgPermission(db, "org.update"), async (req, res, next) => {
    try {
      const name = String(req.body?.name || "").trim().slice(0, 100);
      if (name.length < 2) {
        return res.status(400).json({ detail: "Organisation name must be at least 2 characters" });
      }
      const org = await db.updateDoc("organizations", { id: req.org.id }, { name });
      return res.json(publicOrg(org, req.membership));
    } catch (err) {
      return next(err);
    }
  });

  // ── Team & roles ──────────────────────────────────────────────────────────

  router.get("/:orgId/members", requireOrgPermission(db, "team.read"), async (req, res, next) => {
    try {
      const members = await db.findDocs("memberships", { org_id: req.org.id });
      const visible = members.filter((m) => m.status === "active" || m.status === "invited");
      const out = [];
      for (const m of visible) out.push(await publicMember(db, m));
      return res.json(out);
    } catch (err) {
      return next(err);
    }
  });

  router.post("/:orgId/invites", requireOrgPermission(db, "team.manage"), async (req, res, next) => {
    try {
      const email = normalizeEmail(req.body?.email);
      const role = req.body?.role;
      if (!email) {
        return res.status(400).json({ detail: "Enter a valid email address" });
      }
      if (!isRole(role)) {
        return res.status(400).json({ detail: "Choose a role" });
      }
      if (!canAssign(req.membership.role, role)) {
        return res.status(403).json({ detail: `Only an owner can invite a ${ROLE_LABELS[role]}` });
      }
      const out = await createInvite(db, mailer, { org: req.org, inviter: req.user, email, role });
      if (out.error) {
        return res.status(out.status).json({ detail: out.error });
      }
      return res.status(201).json({ ...(await publicMember(db, out.invite)), dev_link: out.devLink });
    } catch (err) {
      return next(err);
    }
  });

  router.patch(
    "/:orgId/members/:memberId",
    requireOrgPermission(db, "team.manage"),
    async (req, res, next) => {
      try {
        const role = req.body?.role;
        if (!isRole(role)) {
          return res.status(400).json({ detail: "Choose a role" });
        }
        const member = await db.findDoc("memberships", { id: Number(req.params.memberId), org_id: req.org.id });
        if (!member || !["active", "invited"].includes(member.status)) {
          return res.status(404).json({ detail: "Member not found" });
        }
        if (!canAssign(req.membership.role, role) || !canAssign(req.membership.role, member.role)) {
          return res.status(403).json({ detail: "Only an owner can change owners" });
        }
        if (member.role === "owner" && role !== "owner" && (await activeOwnerCount(db, req.org.id)) <= 1) {
          return res.status(409).json({ detail: "An organisation needs at least one owner" });
        }
        const updated = await db.updateDoc("memberships", { id: member.id }, { role, updated_at: nowIso() });
        return res.json(await publicMember(db, updated));
      } catch (err) {
        return next(err);
      }
    },
  );

  router.delete(
    "/:orgId/members/:memberId",
    requireOrgPermission(db, "team.manage"),
    async (req, res, next) => {
      try {
        const member = await db.findDoc("memberships", { id: Number(req.params.memberId), org_id: req.org.id });
        if (!member || !["active", "invited"].includes(member.status)) {
          return res.status(404).json({ detail: "Member not found" });
        }
        if (!canAssign(req.membership.role, member.role)) {
          return res.status(403).json({ detail: "Only an owner can remove an owner" });
        }
        if (member.role === "owner" && member.status === "active" && (await activeOwnerCount(db, req.org.id)) <= 1) {
          return res.status(409).json({ detail: "An organisation needs at least one owner" });
        }
        await db.updateDoc("memberships", { id: member.id }, { status: "revoked", revoked_at: nowIso() });
        return res.status(204).end();
      } catch (err) {
        return next(err);
      }
    },
  );

  return router;
}

async function activeOwnerCount(db, orgId) {
  return (await db.findDocs("memberships", { org_id: orgId, role: "owner", status: "active" })).length;
}

async function findInvite(db, token) {
  if (String(token || "").length < 20) return null;
  const invite = await db.findDoc("memberships", {
    status: "invited",
    invite_token_hash: hashSecret(token),
  });
  if (!invite || Date.parse(invite.expires_at) < Date.now()) return null;
  return invite;
}

/**
 * Accepts an emailed invite for `user`. Returns `{ ok: true }` or
 * `{ status, detail }`. Shared by /api/invites/accept and sign-up/login.
 */
export async function acceptInvite(db, user, token) {
  const invite = await findInvite(db, token);
  if (!invite) {
    return { status: 404, detail: "This invite has expired or was already used" };
  }
  if (user.email && user.email !== invite.invited_email) {
    return {
      status: 409,
      detail: `This invite was sent to ${invite.invited_email}. Sign in with that email to accept it.`,
    };
  }
  const already = await db.findDoc("memberships", { org_id: invite.org_id, user_id: user.id, status: "active" });
  if (already) {
    await db.updateDoc("memberships", { id: invite.id }, { status: "revoked", revoked_at: nowIso() });
    return { status: 409, detail: "You're already a member of this organisation" };
  }
  // Holding the emailed link proves access to that inbox.
  if (!user.email) {
    const taken = await db.findUserByEmail(invite.invited_email);
    if (!taken) {
      await db.updateDoc("users", { id: user.id }, { email: invite.invited_email, email_verified: true });
    }
  }
  await db.updateDoc("memberships", { id: invite.id }, {
    user_id: user.id,
    status: "active",
    invite_token_hash: null,
    accepted_at: nowIso(),
  });
  return { ok: true, orgId: invite.org_id };
}

/** `/api/invites`: preview and accept an emailed invite. */
export function invitesRouter(db) {
  const router = Router();

  router.post("/preview", async (req, res, next) => {
    try {
      const invite = await findInvite(db, req.body?.token);
      if (!invite) {
        return res.status(404).json({ detail: "This invite has expired or was already used" });
      }
      const org = await db.findDoc("organizations", { id: invite.org_id });
      return res.json({
        org_name: org?.name,
        role: invite.role,
        role_label: ROLE_LABELS[invite.role],
        invited_email: invite.invited_email,
      });
    } catch (err) {
      return next(err);
    }
  });

  router.post("/accept", async (req, res, next) => {
    try {
      const out = await acceptInvite(db, req.user, req.body?.token);
      if (!out.ok) {
        return res.status(out.status).json({ detail: out.detail });
      }
      return res.json({ memberships: await membershipsFor(db, req.user.id) });
    } catch (err) {
      return next(err);
    }
  });

  return router;
}
