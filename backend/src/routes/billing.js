import { Router } from "express";

import { InputError, addDays, nowIso, todayStr } from "../bookings/core.js";
import { config } from "../config.js";
import { notify } from "../notify.js";
import { createOrder, verifyPayment } from "../payments/gateway.js";
import { can } from "../roles.js";
import { FEATURE_LABELS, GRACE_DAYS, GST_RATE, PLANS, TRIAL_DAYS, computeStatus, entitlement, priceFor, subscriptionDoc } from "../billing/subscription.js";

/**
 * /api/billing — the owner's Bleiben subscription (plans, trial, checkout,
 * invoices, cancel/resume). Payments use Bleiben's own Razorpay account
 * (BILLING_RAZORPAY_KEY_ID / _SECRET); outside production, test mode is used
 * when no keys are set.
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

export function platformGateway() {
  if (config.billing.razorpayKeyId && config.billing.razorpayKeySecret) {
    return { provider: "razorpay", keyId: config.billing.razorpayKeyId, keySecret: config.billing.razorpayKeySecret };
  }
  return config.isProduction ? null : { provider: "test" };
}

const addMonths = (date, n) => {
  const [y, m, d] = date.split("-").map(Number);
  const t = new Date(Date.UTC(y, m - 1 + n, 1));
  const last = new Date(Date.UTC(t.getUTCFullYear(), t.getUTCMonth() + 1, 0)).getUTCDate();
  t.setUTCDate(Math.min(d, last));
  return t.toISOString().slice(0, 10);
};

async function nextInvoiceNumber(db) {
  const year = todayStr().slice(0, 4);
  const n = (await db.findDocs("invoices", {})).filter((i) => i.number.startsWith(`BLB-${year}-`)).length + 1;
  return `BLB-${year}-${String(n).padStart(5, "0")}`;
}

function publicInvoice(i) {
  const { org_id: _o, ...rest } = i;
  return rest;
}

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

function invoiceHtml(i) {
  const r = (n) => `₹${Number(n).toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  return `<!doctype html><html><head><meta charset="utf-8"><title>Invoice ${esc(i.number)}</title>
<style>body{font-family:system-ui,sans-serif;color:#203C31;max-width:720px;margin:40px auto;padding:0 20px}h1{margin:0}table{width:100%;border-collapse:collapse;margin-top:24px}td,th{padding:8px;border-bottom:1px solid #DEDFD4;text-align:left}.r{text-align:right}.muted{color:#6A7369}</style></head>
<body><h1>${esc(config.appName)}</h1><p class="muted">Tax invoice</p>
<p><b>Invoice</b> ${esc(i.number)}<br><b>Date</b> ${esc(i.issued_on)}<br><b>Billed to</b> ${esc(i.billed_to?.name)}${i.billed_to?.gstin ? `<br>GSTIN ${esc(i.billed_to.gstin)}` : ""}${i.billed_to?.address ? `<br>${esc(i.billed_to.address)}` : ""}</p>
<table><tr><th>Description</th><th class="r">Qty</th><th class="r">Rate</th><th class="r">Amount</th></tr>
<tr><td>${esc(i.description)}<br><span class="muted">${esc(i.period_start)} – ${esc(i.period_end)}</span></td><td class="r">${i.units}</td><td class="r">${r(i.unit_price)}</td><td class="r">${r(i.subtotal)}</td></tr>
<tr><td colspan="3" class="r">GST (${Math.round(GST_RATE * 100)}%)</td><td class="r">${r(i.gst)}</td></tr>
<tr><td colspan="3" class="r"><b>Total paid</b></td><td class="r"><b>${r(i.total)}</b></td></tr></table>
<p class="muted">Payment ${esc(i.payment_id)} · ${esc(i.provider)}</p></body></html>`;
}

export function billingRouter(db, services = {}) {
  const router = Router();
  const fetchImpl = services.fetch ?? fetch;

  const manage = (req) => {
    if (!can(req.membership?.role, "billing.manage")) throw new InputError("Only the owner can manage billing", 403);
  };

  router.get("/plans", handle(async (_req, res) => res.json({
    plans: Object.values(PLANS),
    feature_labels: FEATURE_LABELS,
    trial_days: TRIAL_DAYS,
    grace_days: GRACE_DAYS,
    gst_rate: GST_RATE,
  })));

  router.get("/", handle(async (req, res) => {
    const sub = await subscriptionDoc(db, req.scope.org_id);
    const ent = await entitlement(db, req.scope.org_id);
    const gw = platformGateway();
    return res.json({ ...ent, plan_name: sub.plan ? PLANS[sub.plan].name : "Free trial", history: [...(sub.history ?? [])].reverse(), payment_provider: gw?.provider ?? null });
  }));

  router.post("/quote", handle(async (req, res) => {
    try {
      return res.json(priceFor(req.body?.plan, req.body?.interval, req.body?.units));
    } catch (err) {
      throw new InputError(err.message);
    }
  }));

  // Start a plan purchase / renewal / upgrade.
  router.post("/checkout", handle(async (req, res) => {
    manage(req);
    let price;
    try {
      price = priceFor(req.body?.plan, req.body?.interval, req.body?.units);
    } catch (err) {
      throw new InputError(err.message);
    }
    const ent = await entitlement(db, req.scope.org_id);
    if (price.units < ent.usage.units) throw new InputError(`You have ${ent.usage.units} units in use — buy at least that many`);
    const plan = PLANS[price.plan];
    if (plan.max_properties != null && ent.usage.properties > plan.max_properties) {
      throw new InputError(`${plan.name} allows ${plan.max_properties} properties and you have ${ent.usage.properties}`);
    }
    const gw = platformGateway();
    if (!gw) throw new InputError("Online billing isn't set up yet. Contact Bleiben support.", 503);
    const order = await createOrder(gw, { amount: price.total, receipt: `sub-${req.scope.org_id}-${Date.now()}`, notes: { org: String(req.scope.org_id) } }, fetchImpl);
    const saved = await db.insertDoc("billing_orders", {
      org_id: req.scope.org_id,
      ...price,
      provider: gw.provider,
      order_id: order.orderId,
      status: "created",
      created_by: req.user.id,
      created_at: nowIso(),
    });
    return res.status(201).json({ id: saved.id, provider: gw.provider, order_id: order.orderId, amount: price.total, currency: "INR", key_id: order.keyId ?? null, price });
  }));

  router.post("/checkout/:id/verify", handle(async (req, res) => {
    manage(req);
    const o = await db.findDoc("billing_orders", { id: Number(req.params.id) });
    if (!o || o.org_id !== req.scope.org_id) throw new InputError("Order not found", 404);
    if (o.status === "paid") return res.json({ status: "paid", invoice_id: o.invoice_id });
    const gw = platformGateway();
    const v = verifyPayment(gw, { order_id: o.order_id }, req.body ?? {});
    if (!v.ok) {
      await db.updateDoc("billing_orders", { id: o.id }, { status: "failed", error: v.reason, updated_at: nowIso() });
      const sub = await subscriptionDoc(db, o.org_id);
      await db.updateDoc("subscriptions", { id: sub.id }, { history: [...sub.history, { at: nowIso(), action: "payment_failed", detail: v.reason }] });
      await notify(db, services, { orgId: o.org_id, kind: "subscription", guest: false, extra: { title: "Subscription payment failed", body: v.reason } });
      throw new InputError(`Payment failed: ${v.reason}`, 402);
    }
    const sub = await subscriptionDoc(db, o.org_id);
    const s = computeStatus(sub);
    const today = todayStr();
    // Renewing the same plan before it ends extends from the current end; anything else starts today.
    const renewing = ["active", "cancelling"].includes(s.status) && sub.plan === o.plan && sub.interval === o.interval;
    const start = renewing ? sub.current_period_end : today;
    const end = o.interval === "year" ? addMonths(start, 12) : addMonths(start, 1);
    const action = !sub.plan ? "subscribed" : renewing ? "renewed" : sub.plan !== o.plan ? (PLANS[o.plan].unit_price.month > PLANS[sub.plan].unit_price.month ? "upgraded" : "downgraded") : "changed";
    const org = await db.findDoc("organizations", { id: o.org_id });
    const settings = await db.findDoc("org_settings", { org_id: o.org_id });
    const invoice = await db.insertDoc("invoices", {
      org_id: o.org_id,
      number: await nextInvoiceNumber(db),
      issued_on: today,
      description: `${config.appName} ${PLANS[o.plan].name} plan · ${o.interval === "year" ? "yearly" : "monthly"} · ${o.units} unit(s)`,
      period_start: start,
      period_end: end,
      units: o.units,
      unit_price: o.unit_price,
      subtotal: o.subtotal,
      gst: o.gst,
      total: o.total,
      provider: o.provider,
      payment_id: v.paymentId,
      billed_to: { name: settings?.profile?.legal_name || org?.name, gstin: settings?.profile?.gstin ?? null, address: settings?.profile?.address ?? null },
      created_at: nowIso(),
    });
    await db.updateDoc("billing_orders", { id: o.id }, { status: "paid", payment_id: v.paymentId, invoice_id: invoice.id, updated_at: nowIso() });
    await db.updateDoc("subscriptions", { id: sub.id }, {
      plan: o.plan,
      interval: o.interval,
      units: o.units,
      status: "active",
      current_period_start: start,
      current_period_end: end,
      cancel_at_period_end: false,
      reminders: [],
      history: [...sub.history, { at: nowIso(), action, detail: `${PLANS[o.plan].name} · ${o.units} unit(s) · until ${end} · invoice ${invoice.number}` }],
    });
    return res.json({ status: "paid", invoice_id: invoice.id, entitlement: await entitlement(db, o.org_id) });
  }));

  router.post("/cancel", handle(async (req, res) => {
    manage(req);
    const sub = await subscriptionDoc(db, req.scope.org_id);
    if (!sub.plan || !["active"].includes(computeStatus(sub).status)) throw new InputError("There's no active plan to cancel");
    await db.updateDoc("subscriptions", { id: sub.id }, { cancel_at_period_end: true, history: [...sub.history, { at: nowIso(), action: "cancelled", detail: `Stays active until ${sub.current_period_end}` }] });
    return res.json(await entitlement(db, req.scope.org_id));
  }));

  router.post("/resume", handle(async (req, res) => {
    manage(req);
    const sub = await subscriptionDoc(db, req.scope.org_id);
    if (computeStatus(sub).status !== "cancelling") throw new InputError("Nothing to resume");
    await db.updateDoc("subscriptions", { id: sub.id }, { cancel_at_period_end: false, history: [...sub.history, { at: nowIso(), action: "resumed", detail: "" }] });
    return res.json(await entitlement(db, req.scope.org_id));
  }));

  router.get("/invoices", handle(async (req, res) => {
    const list = (await db.findDocs("invoices", { org_id: req.scope.org_id })).sort((a, b) => b.id - a.id);
    return res.json(list.map(publicInvoice));
  }));

  router.get("/invoices/:id", handle(async (req, res) => {
    const i = await db.findDoc("invoices", { id: Number(req.params.id) });
    if (!i || i.org_id !== req.scope.org_id) throw new InputError("Invoice not found", 404);
    if (req.query.format === "html") {
      res.setHeader("Content-Type", "text/html; charset=utf-8");
      return res.send(invoiceHtml(i));
    }
    return res.json(publicInvoice(i));
  }));

  return router;
}

/**
 * Renewal / reminder worker (runs on a timer): trial ending, plan ending,
 * entering the read-only grace period. Each reminder is sent once.
 */
export async function billingReminders(db, services, today = todayStr()) {
  for (const sub of await db.findDocs("subscriptions", {})) {
    const s = computeStatus(sub, today);
    const sent = new Set(sub.reminders ?? []);
    const due = [];
    const end = sub.plan ? sub.current_period_end : sub.trial_ends_at;
    for (const d of [3, 1]) {
      if (["trialing", "active"].includes(s.status) && addDays(today, d) === end) {
        due.push([`${end}:${d}`, sub.plan ? `Your plan renews in ${d} day(s)` : `Your free trial ends in ${d} day(s)`, sub.plan ? "Renew from Subscription & Billing to avoid interruption." : "Choose a plan to keep using Bleiben without interruption."]);
      }
    }
    if (s.status === "grace") due.push([`${end}:grace`, "Your account is now read-only", `Renew within ${GRACE_DAYS} days to keep your booking page open.`]);
    if (s.status === "expired") due.push([`${end}:expired`, "Your subscription has expired", "Your booking page is closed to new bookings until you renew."]);
    const fresh = due.filter(([k]) => !sent.has(k));
    for (const [, title, body] of fresh) await notify(db, services, { orgId: sub.org_id, kind: "subscription", guest: false, extra: { title, body } });
    if (fresh.length) await db.updateDoc("subscriptions", { id: sub.id }, { reminders: [...sent, ...fresh.map(([k]) => k)] });
  }
}
