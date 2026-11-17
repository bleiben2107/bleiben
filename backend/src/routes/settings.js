import { Router } from "express";

import { InputError, nowIso } from "../bookings/core.js";
import { config } from "../config.js";
import { DEFAULT_NOTIFICATION_PREFS, NOTIFICATION_KINDS, orgPrefs } from "../notify.js";
import { PROVIDERS, checkRazorpayKeys, mask, openSecret, sealSecret, testModeAllowed } from "../payments/gateway.js";
import { can } from "../roles.js";
import { savePhoto } from "../uploads.js";

/**
 * /api/settings — R1 basic settings (MVP plan §2.9): organisation details,
 * property defaults, notification preferences, payment gateway and the
 * activity log. Personal profile/security live under /api/account.
 */

const handle = (fn) => async (req, res, next) => {
  try {
    if (req.scope?.org_id == null) throw new InputError("Choose an organisation (X-Org-Id) first");
    return await fn(req, res);
  } catch (err) {
    if (err instanceof InputError) return res.status(err.status).json({ detail: err.message, ...err.extra });
    return next(err);
  }
};

const POLICIES = ["flexible", "moderate", "strict", "non_refundable"];
const TIME_RE = /^([01]?\d|2[0-3]):[0-5]\d$/;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$/;
const GSTIN_RE = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;

const DEFAULT_PREFERENCES = {
  check_in_time: "13:00",
  check_out_time: "11:00",
  cancellation_policy: "flexible",
  tax_percent: 0,
  prices_include_tax: true,
  default_advance_percent: 0,
  currency: "INR",
};

async function settingsDoc(db, orgId) {
  return (await db.findDoc("org_settings", { org_id: orgId })) ?? (await db.insertDoc("org_settings", { org_id: orgId, profile: {}, preferences: {}, notifications: {}, created_at: nowIso() }));
}

async function gatewayView(db, orgId) {
  const g = await db.findDoc("payment_gateways", { org_id: orgId });
  return {
    provider: g?.enabled ? g.provider : "none",
    providers: Object.fromEntries(Object.entries(PROVIDERS).filter(([k]) => k !== "test" || testModeAllowed())),
    key_id: g?.key_id ?? null,
    key_secret_masked: g?.key_secret ? mask(openSecret(g.key_secret)) : null,
    has_webhook_secret: Boolean(g?.webhook_secret),
    webhook_url: `${config.apiBaseUrl}/api/public/payments/razorpay/${orgId}`,
    verified_at: g?.verified_at ?? null,
    updated_at: g?.updated_at ?? null,
  };
}

export function settingsRouter(db, services = {}) {
  const router = Router();
  const fetchImpl = services.fetch ?? fetch;
  const need = (req, permission) => {
    if (!can(req.membership?.role, permission)) throw new InputError("Your role can't change these settings", 403);
  };

  router.get("/", handle(async (req, res) => {
    const org = await db.findDoc("organizations", { id: req.scope.org_id });
    const s = await settingsDoc(db, req.scope.org_id);
    return res.json({
      organization: { name: org.name, ...s.profile },
      preferences: { ...DEFAULT_PREFERENCES, ...s.preferences },
      policies: POLICIES,
      notifications: await orgPrefs(db, req.scope.org_id),
      notification_kinds: NOTIFICATION_KINDS,
      payment_gateway: await gatewayView(db, req.scope.org_id),
    });
  }));

  router.patch("/organization", handle(async (req, res) => {
    need(req, "org.update");
    const b = req.body ?? {};
    const s = await settingsDoc(db, req.scope.org_id);
    const profile = { ...s.profile };
    if (b.name !== undefined) {
      const name = String(b.name).trim().slice(0, 100);
      if (name.length < 2) throw new InputError("Business name must be at least 2 characters");
      await db.updateDoc("organizations", { id: req.scope.org_id }, { name });
    }
    for (const k of ["legal_name", "contact_phone", "website", "description"]) {
      if (b[k] !== undefined) profile[k] = String(b[k]).trim().slice(0, k === "description" ? 500 : 120);
    }
    if (b.contact_email !== undefined) {
      const e = String(b.contact_email).trim().toLowerCase();
      if (e && !EMAIL_RE.test(e)) throw new InputError("Enter a valid contact email");
      profile.contact_email = e;
    }
    if (b.gstin !== undefined) {
      const g = String(b.gstin).trim().toUpperCase();
      if (g && !GSTIN_RE.test(g)) throw new InputError("That GSTIN doesn't look right (15 characters, e.g. 29ABCDE1234F1Z5)");
      profile.gstin = g;
    }
    if (b.address !== undefined) {
      const a = b.address ?? {};
      profile.address_parts = {
        line: String(a.line ?? "").trim().slice(0, 200),
        city: String(a.city ?? "").trim().slice(0, 80),
        state: String(a.state ?? "").trim().slice(0, 80),
        postal_code: String(a.postal_code ?? "").trim().slice(0, 12),
        country: String(a.country ?? "India").trim().slice(0, 60),
      };
      profile.address = Object.values(profile.address_parts).filter(Boolean).join(", ");
    }
    await db.updateDoc("org_settings", { id: s.id }, { profile, updated_at: nowIso() });
    const org = await db.findDoc("organizations", { id: req.scope.org_id });
    return res.json({ name: org.name, ...profile });
  }));

  router.post("/organization/logo", handle(async (req, res) => {
    need(req, "org.update");
    const r = await savePhoto(`logos/${req.scope.org_id}`, req.body);
    if (r.error) throw new InputError(r.error);
    const s = await settingsDoc(db, req.scope.org_id);
    await db.updateDoc("org_settings", { id: s.id }, { profile: { ...s.profile, logo_url: r.url }, updated_at: nowIso() });
    return res.status(201).json({ logo_url: r.url });
  }));

  router.patch("/preferences", handle(async (req, res) => {
    need(req, "org.update");
    const b = req.body ?? {};
    const s = await settingsDoc(db, req.scope.org_id);
    const p = { ...DEFAULT_PREFERENCES, ...s.preferences };
    for (const k of ["check_in_time", "check_out_time"]) {
      if (b[k] !== undefined) {
        if (!TIME_RE.test(String(b[k]))) throw new InputError("Use 24-hour times like 13:00");
        p[k] = String(b[k]);
      }
    }
    if (b.cancellation_policy !== undefined) {
      if (!POLICIES.includes(b.cancellation_policy)) throw new InputError("Choose a cancellation policy");
      p.cancellation_policy = b.cancellation_policy;
    }
    if (b.tax_percent !== undefined) {
      const t = Number(b.tax_percent);
      if (!Number.isFinite(t) || t < 0 || t > 28) throw new InputError("Tax must be between 0 and 28%");
      p.tax_percent = t;
    }
    if (b.prices_include_tax !== undefined) p.prices_include_tax = b.prices_include_tax === true;
    if (b.default_advance_percent !== undefined) {
      const a = Number(b.default_advance_percent);
      if (!Number.isFinite(a) || a < 0 || a > 100) throw new InputError("Advance must be between 0 and 100%");
      p.default_advance_percent = a;
    }
    await db.updateDoc("org_settings", { id: s.id }, { preferences: p, updated_at: nowIso() });
    return res.json(p);
  }));

  router.patch("/notifications", handle(async (req, res) => {
    need(req, "org.update");
    const b = req.body ?? {};
    const s = await settingsDoc(db, req.scope.org_id);
    const cur = await orgPrefs(db, req.scope.org_id);
    const next = { ...cur };
    for (const k of ["guest_email", "guest_sms", "owner_email"]) if (typeof b[k] === "boolean") next[k] = b[k];
    if (b.events && typeof b.events === "object") {
      for (const [k, v] of Object.entries(b.events)) if (k in DEFAULT_NOTIFICATION_PREFS.events && typeof v === "boolean") next.events[k] = v;
    }
    await db.updateDoc("org_settings", { id: s.id }, { notifications: next, updated_at: nowIso() });
    return res.json(next);
  }));

  // Owner's payment gateway (money from direct bookings goes to the owner).
  router.put("/payment-gateway", handle(async (req, res) => {
    need(req, "billing.manage");
    const b = req.body ?? {};
    const provider = String(b.provider ?? "none");
    const existing = await db.findDoc("payment_gateways", { org_id: req.scope.org_id });
    const set = { org_id: req.scope.org_id, provider, enabled: provider !== "none", updated_at: nowIso(), updated_by: req.user.id };
    if (provider === "test" && !testModeAllowed()) throw new InputError("Test mode isn't available here");
    if (provider === "razorpay") {
      const keyId = String(b.key_id ?? existing?.key_id ?? "").trim();
      const secret = b.key_secret ? String(b.key_secret).trim() : existing?.key_secret ? openSecret(existing.key_secret) : "";
      if (!/^rzp_(test|live)_[A-Za-z0-9]{8,}$/.test(keyId)) throw new InputError("Razorpay key IDs look like rzp_live_… or rzp_test_…");
      if (secret.length < 10) throw new InputError("Enter the Razorpay key secret");
      if (b.verify !== false) {
        try {
          await checkRazorpayKeys(keyId, secret, fetchImpl);
          set.verified_at = nowIso();
        } catch (err) {
          throw new InputError(err.message);
        }
      }
      set.key_id = keyId;
      set.key_secret = sealSecret(secret);
      if (b.webhook_secret) set.webhook_secret = sealSecret(String(b.webhook_secret).trim());
    } else if (!["none", "test"].includes(provider)) {
      throw new InputError("Choose Razorpay or turn online payments off");
    }
    if (existing) await db.updateDoc("payment_gateways", { id: existing.id }, set);
    else await db.insertDoc("payment_gateways", { ...set, created_at: nowIso() });
    return res.json(await gatewayView(db, req.scope.org_id));
  }));

  router.get("/activity", handle(async (req, res) => {
    let list = await db.findDocs("audit_logs", { org_id: req.scope.org_id });
    if (req.query.user_id) list = list.filter((l) => l.user_id === Number(req.query.user_id));
    const q = String(req.query.q ?? "").trim().toLowerCase();
    if (q) list = list.filter((l) => `${l.action} ${l.user_name}`.toLowerCase().includes(q));
    list.sort((a, b) => (a.at < b.at ? 1 : -1));
    const page = Math.max(1, Number(req.query.page) || 1);
    const size = 50;
    return res.json({ items: list.slice((page - 1) * size, page * size).map(({ ip: _ip, ...l }) => l), total: list.length, page, page_size: size });
  }));

  return router;
}
