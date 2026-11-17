import crypto from "node:crypto";

import { config } from "../config.js";

/**
 * Owner payment gateways (MVP plan §2.3 "Payment Gateway Settings" and R1
 * "Booking & Payments": gateway, webhooks, verification).
 *
 * Providers:
 *  - razorpay: the owner's own Razorpay account. Orders are created with the
 *    owner's keys and payments are verified by signature (checkout) or by the
 *    signed webhook. Money goes straight to the owner.
 *  - test: Bleiben test mode for development only — refused in production so
 *    a booking can never be confirmed without a real payment.
 */

export const PROVIDERS = { razorpay: "Razorpay", test: "Test mode (no real money)" };

// ── Secrets at rest ─────────────────────────────────────────────────────────
const key = () => crypto.createHash("sha256").update(`${config.secretKey}:payment-gateway`).digest();

export function sealSecret(plain) {
  if (!plain) return null;
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv("aes-256-gcm", key(), iv);
  const enc = Buffer.concat([c.update(String(plain), "utf8"), c.final()]);
  return `v1.${iv.toString("base64url")}.${c.getAuthTag().toString("base64url")}.${enc.toString("base64url")}`;
}

export function openSecret(sealed) {
  if (!sealed) return null;
  const [v, iv, tag, enc] = String(sealed).split(".");
  if (v !== "v1") return null;
  const d = crypto.createDecipheriv("aes-256-gcm", key(), Buffer.from(iv, "base64url"));
  d.setAuthTag(Buffer.from(tag, "base64url"));
  return Buffer.concat([d.update(Buffer.from(enc, "base64url")), d.final()]).toString("utf8");
}

export const mask = (s) => (s ? `${String(s).slice(0, 8)}…${String(s).slice(-4)}` : null);

const hmac = (secret, data) => crypto.createHmac("sha256", secret).update(data).digest("hex");
const safeEqual = (a, b) => {
  const x = Buffer.from(String(a ?? ""));
  const y = Buffer.from(String(b ?? ""));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
};

export function testModeAllowed() {
  return !config.isProduction;
}

/** The org's gateway with decrypted secrets, or null when not set up. */
export async function orgGateway(db, orgId) {
  const g = await db.findDoc("payment_gateways", { org_id: orgId });
  if (!g || g.provider === "none" || !g.enabled) return null;
  if (g.provider === "test") return testModeAllowed() ? { provider: "test" } : null;
  if (g.provider === "razorpay") {
    return { provider: "razorpay", keyId: g.key_id, keySecret: openSecret(g.key_secret), webhookSecret: openSecret(g.webhook_secret) };
  }
  return null;
}

/**
 * Creates a gateway order for `amount` rupees.
 * Returns { orderId, amount, currency, keyId? }.
 */
export async function createOrder(gw, { amount, receipt, notes }, fetchImpl = fetch) {
  const paise = Math.round(amount * 100);
  if (gw.provider === "test") {
    return { orderId: `test_order_${crypto.randomBytes(8).toString("hex")}`, amount, currency: "INR" };
  }
  if (gw.provider === "razorpay") {
    const res = await fetchImpl("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${Buffer.from(`${gw.keyId}:${gw.keySecret}`).toString("base64")}`,
      },
      body: JSON.stringify({ amount: paise, currency: "INR", receipt: String(receipt).slice(0, 40), notes }),
      signal: AbortSignal.timeout(15000),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body?.error?.description || `Razorpay returned ${res.status}`);
    return { orderId: body.id, amount, currency: body.currency ?? "INR", keyId: gw.keyId };
  }
  throw new Error("No payment gateway");
}

/** Checkout-callback verification. Returns { ok, paymentId, reason }. */
export function verifyPayment(gw, attempt, body) {
  if (gw.provider === "test") {
    if (body?.test_outcome === "success") return { ok: true, paymentId: `test_pay_${crypto.randomBytes(6).toString("hex")}` };
    return { ok: false, reason: body?.reason || "The test payment was declined" };
  }
  if (gw.provider === "razorpay") {
    if (body?.error) return { ok: false, reason: String(body.error?.description ?? body.error).slice(0, 200) };
    const { razorpay_order_id: orderId, razorpay_payment_id: paymentId, razorpay_signature: sig } = body ?? {};
    if (orderId !== attempt.order_id || !paymentId) return { ok: false, reason: "Payment details don't match this order" };
    const ok = safeEqual(hmac(gw.keySecret, `${orderId}|${paymentId}`), sig);
    return ok ? { ok: true, paymentId } : { ok: false, reason: "Payment signature check failed" };
  }
  return { ok: false, reason: "No payment gateway" };
}

export function verifyWebhook(gw, rawBody, signature) {
  if (gw?.provider !== "razorpay" || !gw.webhookSecret) return false;
  return safeEqual(hmac(gw.webhookSecret, rawBody), signature);
}

/** Checks Razorpay keys by listing one order. */
export async function checkRazorpayKeys(keyId, keySecret, fetchImpl = fetch) {
  const res = await fetchImpl("https://api.razorpay.com/v1/orders?count=1", {
    headers: { Authorization: `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString("base64")}` },
    signal: AbortSignal.timeout(15000),
  });
  if (res.status === 401) throw new Error("Razorpay rejected these keys");
  if (!res.ok) throw new Error(`Razorpay returned ${res.status}`);
  return true;
}
