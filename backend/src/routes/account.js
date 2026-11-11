import { Router } from "express";

import { config } from "../config.js";
import { otpEmail } from "../messaging.js";
import { publicUser } from "../security.js";
import { maskPhone, normalizeEmail, normalizePhone } from "../tokens.js";
import { savePhoto } from "../uploads.js";
import { HttpError, consumeChallenge, handle, issueChallenge } from "./auth.js";

const NAME_RE = /^[a-zA-Z]+(?:\s[a-zA-Z]+)*$/;
const PINCODE_RE = /^\d{6}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Optional free-text profile fields (Account settings → Personal info) and
 * their maximum lengths.
 */
const TEXT_FIELDS = {
  preferred_name: 50,
  address1: 120,
  address2: 120,
  country: 60,
  state: 60,
  city: 60,
  profession: 80,
  hobbies: 200,
  pet_name: 50,
  languages: 120,
  school: 120,
  about: 500,
};

/** Validates a Personal info update. Returns the clean profile + name. */
function validateProfile(body) {
  const first = String(body?.first_name ?? "").trim().replace(/\s+/g, " ");
  const last = String(body?.last_name ?? "").trim().replace(/\s+/g, " ");
  if (!first) throw new HttpError(400, "First name is required");
  if (!NAME_RE.test(first) || (last && !NAME_RE.test(last))) {
    throw new HttpError(400, "Only alphabets are allowed in the name");
  }
  if (first.length > 40 || last.length > 40) throw new HttpError(400, "Name is too long — 40 characters at most");

  const profile = { first_name: first, last_name: last };
  for (const [key, max] of Object.entries(TEXT_FIELDS)) {
    const value = String(body?.[key] ?? "").trim();
    if (value.length > max) {
      throw new HttpError(400, `${key === "about" ? "About yourself" : key.replace("_", " ")} is too long — ${max} characters at most`);
    }
    profile[key] = value;
  }

  const dob = String(body?.date_of_birth ?? "").trim();
  if (dob) {
    const date = new Date(`${dob}T00:00:00Z`);
    if (!DATE_RE.test(dob) || Number.isNaN(date.getTime()) || date > new Date()) {
      throw new HttpError(400, "Enter a valid date of birth");
    }
  }
  profile.date_of_birth = dob;

  const pincode = String(body?.pincode ?? "").trim();
  if (pincode && !PINCODE_RE.test(pincode)) throw new HttpError(400, "Pincode should be 6 digits");
  profile.pincode = pincode;

  profile.email_notifications = body?.email_notifications !== false;
  return { profile, name: [first, last].filter(Boolean).join(" ") };
}

/**
 * Account settings for the signed-in user (homyhuts: /account/profile-info and
 * /account/verification). Organisation roles live under /api/orgs/:id/members.
 */
export function accountRouter(db, { mailer, sms }) {
  const router = Router();
  const minutes = Math.round(config.otp.ttlSeconds / 60);

  function otpSentBody(sentTo, code, delivered) {
    const body = { sent_to: sentTo, expires_in: config.otp.ttlSeconds, resend_in: config.otp.resendCooldownSeconds };
    if (!delivered && !config.isProduction) body.dev_code = code;
    return body;
  }

  router.get("/", (req, res) => res.json(publicUser(req.user)));

  // ── Personal info ─────────────────────────────────────────────────────────

  router.patch(
    "/profile",
    handle(async (req, res) => {
      const { profile, name } = validateProfile(req.body);
      const user = await db.updateDoc("users", { id: req.user.id }, { name, profile, updated_at: new Date().toISOString() });
      return res.json(publicUser(user));
    }),
  );

  router.post(
    "/avatar",
    handle(async (req, res) => {
      const { url, error } = await savePhoto("avatars", req.body);
      if (error) throw new HttpError(400, error);
      const user = await db.updateDoc("users", { id: req.user.id }, { avatar_url: url });
      return res.json(publicUser(user));
    }),
  );

  // ── Email / phone: change or add, confirmed with an OTP to the new value ─

  function contactTarget(body) {
    const channel = body?.channel;
    if (channel === "email") {
      const email = normalizeEmail(body?.value);
      if (!email) throw new HttpError(400, "Enter a valid email address");
      return { channel, target: email, purpose: "change_email" };
    }
    if (channel === "phone") {
      const phone = normalizePhone(body?.value, body?.country_code);
      if (!phone) throw new HttpError(400, "Enter a valid phone number (10–15 digits)");
      return { channel, target: phone, purpose: "add_phone" };
    }
    throw new HttpError(400, "Choose email or phone");
  }

  async function ensureAvailable(channel, target, userId) {
    const owner = channel === "email" ? await db.findUserByEmail(target) : await db.findDoc("users", { phone: target });
    if (owner && owner.id !== userId) {
      throw new HttpError(409, `This ${channel === "email" ? "email" : "phone number"} is already linked to another account`);
    }
    if (owner && owner.id === userId && owner[`${channel}_verified`]) {
      throw new HttpError(409, `This ${channel === "email" ? "email" : "phone number"} is already on your account`);
    }
  }

  router.post(
    "/contact/request-otp",
    handle(async (req, res) => {
      const { channel, target, purpose } = contactTarget(req.body);
      await ensureAvailable(channel, target, req.user.id);
      const code = await issueChallenge(db, { channel, target, purpose, pending: { user_id: req.user.id } });
      if (channel === "email") {
        await mailer.send({ to: target, ...otpEmail(code, minutes, purpose) });
        return res.status(202).json({ ...otpSentBody(target, code, mailer.configured), channel });
      }
      const result = await sms.send({ to: target, text: `${code} is your Bleiben OTP. It expires in ${minutes} minutes.` });
      return res.status(202).json({ ...otpSentBody(maskPhone(target), code, result?.delivered), channel });
    }),
  );

  router.post(
    "/contact/verify-otp",
    handle(async (req, res) => {
      const { channel, target, purpose } = contactTarget(req.body);
      const challenge = await consumeChallenge(db, { channel, target, purpose, code: req.body?.code });
      // The code was issued to this user only.
      if (challenge.pending?.user_id !== req.user.id) {
        throw new HttpError(400, "This OTP has expired. Request a new one.");
      }
      await ensureAvailable(channel, target, req.user.id);
      const user = await db.updateDoc(
        "users",
        { id: req.user.id },
        channel === "email" ? { email: target, email_verified: true } : { phone: target, phone_verified: true },
      );
      return res.json(publicUser(user));
    }),
  );

  return router;
}
