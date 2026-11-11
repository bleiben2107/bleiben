import { Router } from "express";

import { config } from "../config.js";
import { otpEmail } from "../messaging.js";
import { membershipsFor, sessionResponse } from "../session.js";
import { acceptInvite, provisionOrganization } from "./orgs.js";
import {
  generateOtp,
  hashSecret,
  maskPhone,
  normalizeEmail,
  normalizePhone,
  secretsMatch,
} from "../tokens.js";

const nowIso = () => new Date().toISOString();
const secondsSince = (iso) => (Date.now() - Date.parse(iso)) / 1000;
const NAME_RE = /^[a-zA-Z]+(?:\s[a-zA-Z]+)*$/;

export class HttpError extends Error {
  constructor(status, detail, extra = {}) {
    super(detail);
    this.status = status;
    this.extra = extra;
  }
}

/**
 * Creates a fresh OTP challenge for `channel`/`target` after enforcing the
 * resend cooldown and hourly limit. Returns the plain code (never stored).
 */
export async function issueChallenge(db, { channel, target, purpose, pending = null }) {
  const recent = (await db.findDocs("otp_challenges", { channel, target }))
    .filter((c) => secondsSince(c.created_at) < 3600)
    .sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
  // Cooldown applies to resending a still-pending code, not to a new request
  // after the previous code was used (e.g. log in right after signing up).
  const open = recent.find((c) => !c.consumed_at);
  if (open && secondsSince(open.created_at) < config.otp.resendCooldownSeconds) {
    const wait = Math.ceil(config.otp.resendCooldownSeconds - secondsSince(open.created_at));
    throw new HttpError(429, `Please wait ${wait}s before requesting a new code`, { retry_after: wait });
  }
  if (recent.length >= config.otp.maxSendsPerHour) {
    throw new HttpError(429, "Too many codes requested. Try again in an hour.");
  }
  // A new code replaces any earlier unused one.
  await db.deleteDocs("otp_challenges", { channel, target, consumed_at: null });
  const code = generateOtp();
  await db.insertDoc("otp_challenges", {
    channel,
    target,
    purpose,
    pending,
    code_hash: hashSecret(code),
    attempts: 0,
    expires_at: new Date(Date.now() + config.otp.ttlSeconds * 1000).toISOString(),
    consumed_at: null,
    created_at: nowIso(),
  });
  return code;
}

/** Checks a code against the open challenge and consumes it on success. */
export async function consumeChallenge(db, { channel, target, purpose, code }) {
  if (!/^\d{6}$/.test(String(code || "").trim())) {
    throw new HttpError(400, "Enter the 6-digit OTP");
  }
  const challenge = await db.findDoc("otp_challenges", { channel, target, consumed_at: null });
  if (!challenge || (purpose && challenge.purpose !== purpose) || Date.parse(challenge.expires_at) < Date.now()) {
    throw new HttpError(400, "This OTP has expired. Request a new one.");
  }
  if (challenge.attempts >= config.otp.maxAttempts) {
    throw new HttpError(429, "Too many wrong attempts. Request a new OTP.");
  }
  if (!secretsMatch(String(code).trim(), challenge.code_hash)) {
    const attempts = challenge.attempts + 1;
    await db.updateDoc("otp_challenges", { id: challenge.id }, { attempts });
    const left = config.otp.maxAttempts - attempts;
    throw new HttpError(
      400,
      left > 0 ? `Incorrect OTP. ${left} attempt${left === 1 ? "" : "s"} left.` : "Too many wrong attempts. Request a new OTP.",
    );
  }
  await db.updateDoc("otp_challenges", { id: challenge.id }, { consumed_at: nowIso() });
  return challenge;
}

/**
 * PRD AUTH-3: every account works inside an organisation. Joins the org from
 * an invite link when one is given; otherwise creates one with the user as
 * Owner, named after them (renameable later).
 */
async function ensureOrganization(db, user, inviteToken) {
  if (inviteToken) {
    const out = await acceptInvite(db, user, inviteToken);
    if (out.ok) return { invite: "accepted" };
    if ((await membershipsFor(db, user.id)).length) return { invite: out.detail };
    await provisionOrganization(db, user, user.name || "My properties");
    return { invite: out.detail };
  }
  if ((await membershipsFor(db, user.id)).length === 0) {
    await provisionOrganization(db, user, user.name || "My properties");
  }
  return {};
}

/** Wraps a handler so HttpError becomes a JSON error response. */
export const handle = (fn) => async (req, res, next) => {
  try {
    return await fn(req, res);
  } catch (err) {
    if (err instanceof HttpError) {
      return res.status(err.status).json({ detail: err.message, ...err.extra });
    }
    return next(err);
  }
};

function validateSignup(body) {
  const name = String(body?.name || "").trim().replace(/\s+/g, " ");
  if (!name) throw new HttpError(400, "Name is required");
  if (!NAME_RE.test(name)) throw new HttpError(400, "Only alphabets are allowed in the name");
  if (name.length > 75) throw new HttpError(400, "Name is too long — 75 characters at most");
  const email = normalizeEmail(body?.email);
  if (!email) throw new HttpError(400, "Enter a valid email address");
  let phone = null;
  if (String(body?.phone || "").trim()) {
    phone = normalizePhone(body.phone, body.country_code);
    if (!phone) throw new HttpError(400, "Enter a valid phone number (10–15 digits)");
  }
  return { name, email, phone };
}

export function authRouter(db, { mailer, sms }) {
  const router = Router();
  const minutes = Math.round(config.otp.ttlSeconds / 60);

  async function sendEmailOtp(email, code, purpose) {
    await mailer.send({ to: email, ...otpEmail(code, minutes, purpose) });
  }

  function otpSentBody(sentTo, code, delivered) {
    const body = { sent_to: sentTo, expires_in: config.otp.ttlSeconds, resend_in: config.otp.resendCooldownSeconds };
    // Without a real provider, outside production, hand the code back for testing.
    if (!delivered && !config.isProduction) body.dev_code = code;
    return body;
  }

  // ── Sign up: name + email (required) + phone (optional) → OTP to email ───

  router.post(
    "/signup/request-otp",
    handle(async (req, res) => {
      const { name, email, phone } = validateSignup(req.body);
      if (await db.findUserByEmail(email)) {
        throw new HttpError(409, "An account with this email already exists. Please log in.", { action: "login" });
      }
      if (phone && (await db.findDoc("users", { phone }))) {
        throw new HttpError(409, "This phone number is already linked to an account. Please log in.", { action: "login" });
      }
      const code = await issueChallenge(db, {
        channel: "email",
        target: email,
        purpose: "signup",
        pending: { name, phone },
      });
      await sendEmailOtp(email, code, "signup");
      return res.status(202).json(otpSentBody(email, code, mailer.configured));
    }),
  );

  router.post(
    "/signup/verify-otp",
    handle(async (req, res) => {
      const email = normalizeEmail(req.body?.email);
      if (!email) throw new HttpError(400, "Enter a valid email address");
      const challenge = await consumeChallenge(db, {
        channel: "email",
        target: email,
        purpose: "signup",
        code: req.body?.code,
      });
      if (await db.findUserByEmail(email)) {
        throw new HttpError(409, "An account with this email already exists. Please log in.", { action: "login" });
      }
      const pending = challenge.pending ?? {};
      const user = await db.insertDoc("users", {
        name: pending.name ?? "",
        email,
        email_verified: true,
        phone: pending.phone ?? null,
        phone_verified: false,
        created_at: nowIso(),
      });
      const joined = await ensureOrganization(db, user, req.body?.invite_token);
      return res.status(201).json(await sessionResponse(db, user, { is_new_user: true, ...joined }));
    }),
  );

  // ── Log in: one field, email or phone → OTP ─────────────────────────────

  router.post(
    "/login/request-otp",
    handle(async (req, res) => {
      const raw = String(req.body?.identifier || "").trim();
      if (!raw) throw new HttpError(400, "Enter your email or phone number");

      if (/^[+\d\s-]+$/.test(raw)) {
        const phone = normalizePhone(raw, req.body?.country_code);
        if (!phone) throw new HttpError(400, "Enter a valid phone number");
        const user = await db.findDoc("users", { phone });
        if (!user) {
          throw new HttpError(404, "No account found with this phone number. Please sign up.", { action: "signup" });
        }
        const code = await issueChallenge(db, { channel: "phone", target: phone, purpose: "login" });
        const result = await sms.send({ to: phone, text: `${code} is your Bleiben OTP. It expires in ${minutes} minutes.` });
        return res.status(202).json({ ...otpSentBody(maskPhone(phone), code, result?.delivered), channel: "phone" });
      }

      const email = normalizeEmail(raw);
      if (!email) throw new HttpError(400, "Enter a valid email address");
      const user = await db.findUserByEmail(email);
      if (!user) {
        throw new HttpError(404, "No account found with this email. Please sign up.", { action: "signup" });
      }
      const code = await issueChallenge(db, { channel: "email", target: email, purpose: "login" });
      await sendEmailOtp(email, code, "login");
      return res.status(202).json({ ...otpSentBody(email, code, mailer.configured), channel: "email" });
    }),
  );

  router.post(
    "/login/verify-otp",
    handle(async (req, res) => {
      const raw = String(req.body?.identifier || "").trim();
      const isPhone = /^[+\d\s-]+$/.test(raw);
      const target = isPhone ? normalizePhone(raw, req.body?.country_code) : normalizeEmail(raw);
      if (!target) throw new HttpError(400, "Enter your email or phone number");
      const channel = isPhone ? "phone" : "email";
      await consumeChallenge(db, { channel, target, purpose: "login", code: req.body?.code });

      let user = isPhone ? await db.findDoc("users", { phone: target }) : await db.findUserByEmail(target);
      if (!user) throw new HttpError(404, "No account found. Please sign up.", { action: "signup" });
      const verifiedField = isPhone ? "phone_verified" : "email_verified";
      if (!user[verifiedField]) {
        user = await db.updateDoc("users", { id: user.id }, { [verifiedField]: true });
      }
      const joined = await ensureOrganization(db, user, req.body?.invite_token);
      return res.json(await sessionResponse(db, user, joined));
    }),
  );

  return router;
}
