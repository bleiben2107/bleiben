import { addDays, nowIso, todayStr } from "../bookings/core.js";

/**
 * Subscription & Billing (MVP plan §2.11).
 *
 * PLACEHOLDER PRICES — set the real numbers here before launch.
 * Prices are per unit (room unit) and exclude GST; GST is added on invoices.
 */
export const PLANS = {
  starter: {
    id: "starter",
    name: "Starter",
    tagline: "For a single homestay getting online",
    unit_price: { month: 249, year: 2490 },
    max_properties: 2,
    max_units: 10,
    features: ["dashboard", "calendar", "properties", "reservations", "booking_page", "channel_manager", "notifications"],
  },
  growth: {
    id: "growth",
    name: "Growth",
    tagline: "For hosts running several properties with a team",
    unit_price: { month: 349, year: 3490 },
    max_properties: null,
    max_units: null,
    features: ["dashboard", "calendar", "properties", "reservations", "booking_page", "channel_manager", "notifications", "expenses", "inbox", "team"],
  },
};

export const FEATURE_LABELS = {
  dashboard: "Dashboard",
  calendar: "Calendar & holds",
  properties: "Properties & rooms",
  reservations: "Reservations",
  booking_page: "Direct booking page",
  channel_manager: "iCal channel manager",
  notifications: "Email/SMS notifications",
  expenses: "Expenses & profit",
  inbox: "Guest inbox",
  team: "Team members beyond the owner",
};

export const TRIAL_DAYS = 14;
export const GRACE_DAYS = 7;
export const GST_RATE = 0.18;
const TRIAL_LIMITS = { max_properties: null, max_units: 20 };

const day = (iso) => String(iso).slice(0, 10);

/** The org's subscription document, creating the 14-day trial on first use. */
export async function subscriptionDoc(db, orgId) {
  let sub = await db.findDoc("subscriptions", { org_id: orgId });
  if (!sub) {
    const org = await db.findDoc("organizations", { id: orgId });
    const start = day(org?.created_at ?? nowIso());
    sub = await db.insertDoc("subscriptions", {
      org_id: orgId,
      plan: null,
      interval: null,
      units: 0,
      status: "trialing",
      trial_started_at: start,
      trial_ends_at: addDays(start, TRIAL_DAYS),
      current_period_start: null,
      current_period_end: null,
      cancel_at_period_end: false,
      history: [{ at: nowIso(), action: "trial_started", detail: `${TRIAL_DAYS}-day free trial` }],
      reminders: [],
      created_at: nowIso(),
    });
  }
  return sub;
}

/** Live status from dates: trialing | active | cancelling | grace | expired. */
export function computeStatus(sub, today = todayStr()) {
  if (sub.status === "trialing" || !sub.plan) {
    const end = sub.trial_ends_at;
    if (today < end) return { status: "trialing", ends: end };
    const grace = addDays(end, GRACE_DAYS);
    return today < grace ? { status: "grace", ends: grace, reason: "trial_ended" } : { status: "expired", ends: null, reason: "trial_ended" };
  }
  const end = sub.current_period_end;
  if (today < end) return { status: sub.cancel_at_period_end ? "cancelling" : "active", ends: end };
  if (sub.cancel_at_period_end) return { status: "expired", ends: null, reason: "cancelled" };
  const grace = addDays(end, GRACE_DAYS);
  return today < grace ? { status: "grace", ends: grace, reason: "payment_due" } : { status: "expired", ends: null, reason: "payment_due" };
}

async function usage(db, orgId) {
  const props = (await db.findDocs("properties", { org_id: orgId })).filter((p) => p.status !== "deleted");
  let units = 0;
  for (const p of props) {
    for (const r of await db.findDocs("rooms", { property_id: p.id })) if (r.status !== "archived") units += r.unitCount ?? 1;
  }
  return { properties: props.length, units };
}

/**
 * What the org may do now. read_only during grace/expired; the public
 * booking page closes once expired (guests aren't affected during grace).
 */
export async function entitlement(db, orgId) {
  const sub = await subscriptionDoc(db, orgId);
  const s = computeStatus(sub);
  const plan = sub.plan ? PLANS[sub.plan] : null;
  const trial = !plan;
  const limits = trial
    ? TRIAL_LIMITS
    : { max_properties: plan.max_properties, max_units: Math.min(plan.max_units ?? Infinity, sub.units || Infinity) };
  return {
    status: s.status,
    status_ends: s.ends,
    reason: s.reason ?? null,
    plan: sub.plan,
    interval: sub.interval,
    units: sub.units,
    trial_ends_at: sub.trial_ends_at,
    current_period_end: sub.current_period_end,
    cancel_at_period_end: !!sub.cancel_at_period_end,
    read_only: ["grace", "expired"].includes(s.status),
    bookable: s.status !== "expired",
    features: trial ? Object.keys(FEATURE_LABELS) : plan.features,
    limits: { max_properties: limits.max_properties ?? null, max_units: Number.isFinite(limits.max_units) ? limits.max_units : null },
    usage: await usage(db, orgId),
  };
}

/** Express middleware: blocks writes while the subscription is read-only. */
export function requireWritable(db) {
  return async (req, res, next) => {
    try {
      if (["GET", "HEAD"].includes(req.method) || req.scope?.org_id == null) return next();
      const e = await entitlement(db, req.scope.org_id);
      if (e.read_only) {
        return res.status(402).json({
          code: "subscription_read_only",
          detail: e.reason === "trial_ended"
            ? "Your free trial has ended. Choose a plan in Subscription & Billing to keep making changes."
            : "Your subscription needs renewing. You can view everything, but changes are paused until you renew.",
        });
      }
      return next();
    } catch (err) {
      return next(err);
    }
  };
}

/** Express middleware: feature not in the org's plan → 402. */
export function requireFeature(db, feature) {
  return async (req, res, next) => {
    try {
      if (req.scope?.org_id == null) return next();
      const e = await entitlement(db, req.scope.org_id);
      if (!e.features.includes(feature)) {
        return res.status(402).json({ code: "plan_feature", feature, detail: `${FEATURE_LABELS[feature]} is part of the Growth plan. Upgrade in Subscription & Billing.` });
      }
      return next();
    } catch (err) {
      return next(err);
    }
  };
}

/** Throws a 402-style error when adding `addUnits` / `addProperties` would exceed the plan. */
export async function assertWithinLimits(db, orgId, { addUnits = 0, addProperties = 0 } = {}) {
  const e = await entitlement(db, orgId);
  const { max_units: mu, max_properties: mp } = e.limits;
  if (mp != null && addProperties > 0 && e.usage.properties + addProperties > mp) {
    const err = new Error(`Your plan allows ${mp} properties. Upgrade in Subscription & Billing to add more.`);
    err.status = 402;
    throw err;
  }
  if (mu != null && addUnits > 0 && e.usage.units + addUnits > mu) {
    const err = new Error(`Your plan covers ${mu} units (${e.usage.units} in use). Add units in Subscription & Billing.`);
    err.status = 402;
    throw err;
  }
}

export function priceFor(planId, interval, units) {
  const plan = PLANS[planId];
  if (!plan) throw new Error("Unknown plan");
  if (!["month", "year"].includes(interval)) throw new Error("Choose monthly or yearly billing");
  const n = Math.floor(Number(units));
  if (!Number.isInteger(n) || n < 1 || n > 1000) throw new Error("Choose between 1 and 1000 units");
  if (plan.max_units != null && n > plan.max_units) throw new Error(`${plan.name} covers up to ${plan.max_units} units`);
  const subtotal = plan.unit_price[interval] * n;
  const gst = Math.round(subtotal * GST_RATE * 100) / 100;
  return { plan: planId, interval, units: n, unit_price: plan.unit_price[interval], subtotal, gst, total: Math.round((subtotal + gst) * 100) / 100 };
}
