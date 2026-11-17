import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import test from "node:test";

import { createApp } from "../src/app.js";
import { addDays, todayStr } from "../src/bookings/core.js";
import { createDb } from "../src/db.js";
import { billingReminders } from "../src/routes/billing.js";
import { syncDueConnections } from "../src/routes/channels.js";

function memoryDb(t) {
  const filePath = `./data/test-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.json`;
  t.after(() => fs.rmSync(filePath, { force: true }));
  return createDb(filePath);
}

/** Fake mailer/SMS + a fake fetch serving iCal feeds and the Razorpay API. */
function fakeServices() {
  const mail = [];
  const sms = [];
  const feeds = new Map();
  const razorpay = { orders: [], keysOk: true };
  const fetch = async (url, init = {}) => {
    const u = String(url);
    if (u.startsWith("https://api.razorpay.com/v1/orders")) {
      if (!razorpay.keysOk) return new Response("{}", { status: 401 });
      if ((init.method ?? "GET") === "GET") return Response.json({ items: [] });
      const body = JSON.parse(init.body);
      const order = { id: `order_${crypto.randomBytes(5).toString("hex")}`, currency: "INR", amount: body.amount };
      razorpay.orders.push(order);
      return Response.json(order);
    }
    if (feeds.has(u)) return new Response(feeds.get(u), { status: 200 });
    return new Response("not found", { status: 404 });
  };
  return {
    mail,
    sms,
    feeds,
    razorpay,
    services: {
      mailer: { configured: true, send: async (m) => (mail.push(m), { delivered: true }) },
      sms: { configured: true, send: async (m) => (sms.push(m), { delivered: true }) },
      fetch,
    },
  };
}

async function withServer(db, services, run) {
  const app = createApp(db, services);
  const server = app.listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, { token, body, org, raw, headers: extra } = {}) => {
    const headers = { "Content-Type": "application/json", ...(extra ?? {}) };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (org) headers["X-Org-Id"] = String(org);
    const res = await fetch(`${base}${path}`, { method, headers, body: raw ?? (body ? JSON.stringify(body) : undefined) });
    const text = await res.text();
    let parsed = text;
    try {
      parsed = text ? JSON.parse(text) : null;
    } catch {
      /* text */
    }
    return { status: res.status, body: parsed, headers: res.headers };
  };
  try {
    await run(call);
  } finally {
    await new Promise((r) => server.close(r));
  }
}

const codeFrom = (list) => (list.filter((m) => /\d{6}/.test(m.text)).at(-1).text.match(/\d{6}/) ?? [])[0];

async function signUp(call, fakes, name, email) {
  await call("POST", "/api/auth/signup/request-otp", { body: { name, email } });
  const v = await call("POST", "/api/auth/signup/verify-otp", { body: { email, code: codeFrom(fakes.mail) } });
  assert.equal(v.status, 201, JSON.stringify(v.body));
  return v.body;
}

const D = (n) => addDays(todayStr(), n);

async function setupHost(call, fakes, { publish = true, units = 1 } = {}) {
  const owner = await signUp(call, fakes, "Asha Host", "asha@example.com");
  const token = owner.access_token;
  const org = owner.memberships[0].org_id;
  const as = (method, path, body) => call(method, path, { token, org, body });
  const prop = await as("POST", "/api/properties", {
    title: "Pine Cottage", propertyType: "Cottage", base_price: 4000, advancePercent: 25, checkInTime: "13:00", address: { city: "Manali", state: "Himachal Pradesh" },
  });
  const room = await as("POST", `/api/properties/${prop.body.id}/rooms`, { name: "Deluxe", max_adults: 2, max_children: 1, unit_count: units });
  assert.equal(room.status, 201, JSON.stringify(room.body));
  let slug = null;
  if (publish) {
    const pub = await as("POST", `/api/properties/${prop.body.id}/publish`);
    assert.equal(pub.status, 200, JSON.stringify(pub.body));
    slug = pub.body.property?.slug ?? pub.body.slug;
  }
  return { owner, token, org, as, prop: prop.body, room: room.body, slug };
}

test("guest booking journey: request mode, test gateway success/failure, hold, notifications", async (t) => {
  const fakes = fakeServices();
  await withServer(memoryDb(t), fakes.services, async (call) => {
    const h = await setupHost(call, fakes);
    assert.ok(h.slug, "published slug");

    // Public page works without login; no gateway → booking requests.
    let stay = await call("GET", `/api/public/stays/${h.slug}`);
    assert.equal(stay.status, 200, JSON.stringify(stay.body));
    assert.equal(stay.body.booking_mode, "request");
    assert.equal(stay.body.rooms[0].name, "Deluxe");
    assert.equal((await call("GET", "/api/public/stays/nope")).status, 404);

    const quote = await call("POST", `/api/public/stays/${h.slug}/quote`, { body: { check_in: D(3), check_out: D(5), adults: 2 } });
    assert.equal(quote.body.rooms[0].available, true);
    assert.equal(quote.body.rooms[0].total, 8000);

    const guest = { name: "Ravi Kumar", phone: "+91 98111 11111", email: "ravi@example.com" };
    const req1 = await call("POST", `/api/public/stays/${h.slug}/book`, { body: { room_id: h.room.id, check_in: D(3), check_out: D(5), adults: 2, guest } });
    assert.equal(req1.status, 201, JSON.stringify(req1.body));
    assert.equal(req1.body.booking.status, "inquiry");
    assert.equal(req1.body.payment, null);
    // An inquiry doesn't hold the room.
    assert.equal((await call("POST", `/api/public/stays/${h.slug}/quote`, { body: { check_in: D(3), check_out: D(5) } })).body.rooms[0].available, true);
    let notes = await h.as("GET", "/api/notifications");
    assert.equal(notes.body.items[0].kind, "booking_created");
    assert.equal((await h.as("GET", "/api/notifications/unread-count")).body.count, 1);

    // Owner turns on test-mode payments.
    const gw = await h.as("PUT", "/api/settings/payment-gateway", { provider: "test" });
    assert.equal(gw.status, 200, JSON.stringify(gw.body));
    stay = await call("GET", `/api/public/stays/${h.slug}`);
    assert.equal(stay.body.booking_mode, "instant");

    // Instant booking: 15-minute hold, 25% advance due now.
    const b2 = await call("POST", `/api/public/stays/${h.slug}/book`, { body: { room_id: h.room.id, check_in: D(10), check_out: D(12), adults: 2, guest } });
    assert.equal(b2.status, 201, JSON.stringify(b2.body));
    assert.equal(b2.body.booking.status, "held");
    assert.ok(b2.body.booking.hold_expires_at);
    assert.equal(b2.body.payment.amount, 2000);
    // The hold blocks the room for others.
    const clash = await call("POST", `/api/public/stays/${h.slug}/book`, { body: { room_id: h.room.id, check_in: D(11), check_out: D(13), guest: { ...guest, email: "" } } });
    assert.equal(clash.status, 409);

    // Wrong token can't verify; failure keeps the hold and notifies.
    assert.equal((await call("POST", `/api/public/payments/${b2.body.payment.attempt_id}/verify`, { body: { token: "nope", test_outcome: "success" } })).status, 404);
    const fail = await call("POST", `/api/public/payments/${b2.body.payment.attempt_id}/verify`, { body: { token: b2.body.token, test_outcome: "failure" } });
    assert.equal(fail.body.payment_status, "failed");
    assert.equal(fail.body.booking.status, "held");
    notes = await h.as("GET", "/api/notifications?kind=payment_failed");
    assert.equal(notes.body.total, 1);

    // Retry and succeed → confirmed, payment recorded, guest emailed.
    const retry = await call("POST", `/api/public/bookings/${b2.body.booking.code}/retry-payment`, { body: { token: b2.body.token } });
    assert.equal(retry.status, 201, JSON.stringify(retry.body));
    const mailsBefore = fakes.mail.length;
    const ok = await call("POST", `/api/public/payments/${retry.body.attempt_id}/verify`, { body: { token: b2.body.token, test_outcome: "success" } });
    assert.equal(ok.body.payment_status, "paid", JSON.stringify(ok.body));
    assert.equal(ok.body.booking.status, "confirmed");
    assert.equal(ok.body.booking.paid, 2000);
    assert.equal(ok.body.booking.balance, 6000);
    const guestMail = fakes.mail.slice(mailsBefore).find((m) => m.to === "ravi@example.com");
    assert.match(guestMail.subject, /confirmed/);
    // Idempotent: verifying again doesn't double-record.
    await call("POST", `/api/public/payments/${retry.body.attempt_id}/verify`, { body: { token: b2.body.token, test_outcome: "success" } });
    const status = await call("GET", `/api/public/bookings/${b2.body.booking.code}?token=${b2.body.token}`);
    assert.equal(status.body.paid, 2000);

    // It appears in the owner's reservations and calendar.
    const list = await h.as("GET", "/api/bookings?q=" + b2.body.booking.code);
    assert.equal(list.body.items[0].status, "confirmed");
    assert.equal(list.body.items[0].source, "direct");
    const cal = await h.as("GET", `/api/calendar?from=${D(10)}&days=3`);
    assert.equal(cal.body.properties[0].rooms[0].bookings.some((x) => x.code === b2.body.booking.code), true);

    // Guest without email gets SMS fallback on cancellation.
    const smsBefore = fakes.sms.length;
    const manual = await h.as("POST", "/api/bookings", { room_id: h.room.id, check_in: D(20), check_out: D(21), guest: { name: "Meera", phone: "+91 98222 22222" }, confirm: true });
    assert.equal(manual.status, 201);
    assert.equal(fakes.sms.length, smsBefore + 1, "confirmation by SMS");
    await h.as("POST", `/api/bookings/${manual.body.id}/cancel`, { reason: "Guest changed plans" });
    assert.match(fakes.sms.at(-1).text, /cancelled/);
    const cancelNote = (await h.as("GET", "/api/notifications?kind=booking_cancelled")).body.items[0];
    assert.ok(cancelNote.deliveries.some((d) => d.channel === "sms" && d.status === "sent"));

    // Notification prefs: turning guest SMS off stops it.
    await h.as("PATCH", "/api/settings/notifications", { guest_sms: false });
    const before = fakes.sms.length;
    await h.as("POST", "/api/bookings", { room_id: h.room.id, check_in: D(22), check_out: D(23), guest: { name: "Kabir", phone: "+91 98333 33333" }, confirm: true });
    assert.equal(fakes.sms.length, before);

    // Read state is per user.
    const first = (await h.as("GET", "/api/notifications")).body.items[0];
    await h.as("POST", `/api/notifications/${first.id}/read`);
    assert.equal((await h.as("GET", "/api/notifications")).body.items[0].read, true);
    await h.as("POST", "/api/notifications/read-all");
    assert.equal((await h.as("GET", "/api/notifications/unread-count")).body.count, 0);

    // Inquiry → confirm re-checks availability.
    const inq = await h.as("POST", "/api/bookings", { room_id: h.room.id, check_in: D(10), check_out: D(11), guest: { name: "Late Lead", phone: "+91 98444 44444" }, inquiry: true });
    assert.equal(inq.body.status, "inquiry");
    assert.equal((await h.as("POST", `/api/bookings/${inq.body.id}/confirm`)).status, 409);

    // Guests directory groups bookings by phone.
    const guests = await h.as("GET", "/api/bookings/guests/list?q=ravi");
    assert.equal(guests.body.items[0].bookings, 2);
    assert.equal(guests.body.items[0].stays, 1);
    const detail = await h.as("GET", `/api/bookings/guests/detail?key=${encodeURIComponent(guests.body.items[0].key)}`);
    assert.equal(detail.body.bookings.length, 2);
  });
});

test("razorpay: owner keys checked, order created, signature and webhook verified", async (t) => {
  const fakes = fakeServices();
  await withServer(memoryDb(t), fakes.services, async (call) => {
    const h = await setupHost(call, fakes);
    assert.equal((await h.as("PUT", "/api/settings/payment-gateway", { provider: "razorpay", key_id: "bad", key_secret: "x" })).status, 400);
    fakes.razorpay.keysOk = false;
    assert.equal((await h.as("PUT", "/api/settings/payment-gateway", { provider: "razorpay", key_id: "rzp_test_ABCDEFGH12", key_secret: "secret_123456" })).status, 400);
    fakes.razorpay.keysOk = true;
    const secret = "secret_123456";
    const webhookSecret = "whsec_abcdef";
    const gw = await h.as("PUT", "/api/settings/payment-gateway", { provider: "razorpay", key_id: "rzp_test_ABCDEFGH12", key_secret: secret, webhook_secret: webhookSecret });
    assert.equal(gw.status, 200, JSON.stringify(gw.body));
    assert.equal(gw.body.provider, "razorpay");
    assert.ok(!JSON.stringify(gw.body).includes(secret), "secret never returned");
    assert.match(gw.body.key_secret_masked, /…/);

    const guest = { name: "Ravi Kumar", phone: "+91 98111 11111", email: "ravi@example.com" };
    const b = await call("POST", `/api/public/stays/${h.slug}/book`, { body: { room_id: h.room.id, check_in: D(3), check_out: D(4), guest } });
    assert.equal(b.status, 201, JSON.stringify(b.body));
    assert.equal(b.body.payment.provider, "razorpay");
    assert.equal(b.body.payment.key_id, "rzp_test_ABCDEFGH12");
    assert.equal(fakes.razorpay.orders.at(-1).amount, 100000, "25% of 4000 in paise");

    const orderId = b.body.payment.order_id;
    const bad = await call("POST", `/api/public/payments/${b.body.payment.attempt_id}/verify`, { body: { token: b.body.token, razorpay_order_id: orderId, razorpay_payment_id: "pay_1", razorpay_signature: "forged" } });
    assert.equal(bad.body.payment_status, "failed");
    // A forged webhook is refused.
    assert.equal((await call("POST", `/api/public/payments/razorpay/${h.org}`, { raw: "{}", headers: { "X-Razorpay-Signature": "nope" } })).status, 400);

    // Retry → valid webhook confirms it.
    const retry = await call("POST", `/api/public/bookings/${b.body.booking.code}/retry-payment`, { body: { token: b.body.token } });
    const payload = JSON.stringify({ event: "payment.captured", payload: { payment: { entity: { id: "pay_ok", order_id: retry.body.order_id } } } });
    const sig = crypto.createHmac("sha256", webhookSecret).update(payload).digest("hex");
    const hook = await call("POST", `/api/public/payments/razorpay/${h.org}`, { raw: payload, headers: { "X-Razorpay-Signature": sig } });
    assert.equal(hook.status, 200, JSON.stringify(hook.body));
    const st = await call("GET", `/api/public/bookings/${b.body.booking.code}?token=${b.body.token}`);
    assert.equal(st.body.status, "confirmed");
    assert.equal(st.body.paid, 1000);

    // Checkout-callback signature path.
    const b2 = await call("POST", `/api/public/stays/${h.slug}/book`, { body: { room_id: h.room.id, check_in: D(6), check_out: D(7), guest } });
    const sig2 = crypto.createHmac("sha256", secret).update(`${b2.body.payment.order_id}|pay_cb`).digest("hex");
    const ok = await call("POST", `/api/public/payments/${b2.body.payment.attempt_id}/verify`, { body: { token: b2.body.token, razorpay_order_id: b2.body.payment.order_id, razorpay_payment_id: "pay_cb", razorpay_signature: sig2 } });
    assert.equal(ok.body.payment_status, "paid", JSON.stringify(ok.body));

    const dash = await h.as("GET", "/api/dashboard?period=next_30");
    assert.equal(dash.body.payments.failed_count, 1);
    assert.equal(dash.body.payments.online_paid, 2000);
  });
});

const ics = (events) => ["BEGIN:VCALENDAR", "VERSION:2.0", ...events.flatMap((e) => [
  "BEGIN:VEVENT", `UID:${e.uid}`, `DTSTART;VALUE=DATE:${e.start.replaceAll("-", "")}`, `DTEND;VALUE=DATE:${e.end.replaceAll("-", "")}`, `SUMMARY:${e.summary}`, "END:VEVENT",
]), "END:VCALENDAR"].join("\r\n");

test("channel manager: iCal connect, import, echo skip, conflict, removal, export, errors", async (t) => {
  const fakes = fakeServices();
  const db = memoryDb(t);
  await withServer(db, fakes.services, async (call) => {
    const h = await setupHost(call, fakes, { units: 1 });
    const url = "https://93.184.216.34/calendar/ical/123.ics";

    // Our own booking that Airbnb will echo back.
    const own = await h.as("POST", "/api/bookings", { room_id: h.room.id, check_in: D(2), check_out: D(4), guest: { name: "Own Guest", phone: "+91 98111 11111" }, confirm: true });
    fakes.feeds.set(url, ics([
      { uid: "air-1", start: D(5), end: D(7), summary: "Reserved" },
      { uid: "air-echo", start: D(2), end: D(4), summary: "Airbnb (Not available)" },
      { uid: "air-block", start: D(9), end: D(10), summary: "Airbnb (Not available)" },
      { uid: "air-clash", start: D(3), end: D(4), summary: "Reserved" },
      { uid: "air-old", start: D(-5), end: D(-3), summary: "Reserved" },
    ]));
    assert.equal((await h.as("POST", "/api/channels", { channel: "airbnb", room_id: h.room.id, url: "ftp://x" })).status, 400);
    assert.equal((await h.as("POST", "/api/channels", { channel: "airbnb", room_id: h.room.id, url: "https://127.0.0.1/x.ics" })).status, 400, "private address refused");
    const c = await h.as("POST", "/api/channels", { channel: "airbnb", room_id: h.room.id, url });
    assert.equal(c.status, 201, JSON.stringify(c.body));
    assert.equal(c.body.first_sync.added, 3, JSON.stringify(c.body.first_sync));
    assert.equal(c.body.first_sync.skipped_echo, 1);
    assert.equal(c.body.first_sync.conflicts, 1);
    assert.ok(!JSON.stringify(c.body).includes("/calendar/ical/123.ics"), "feed URL masked");
    assert.equal((await h.as("POST", "/api/channels", { channel: "airbnb", room_id: h.room.id, url })).status, 400, "duplicate");

    // Imported reservation shows in reservations; external block doesn't.
    const res = await h.as("GET", "/api/bookings?source=airbnb");
    assert.equal(res.body.items.length, 2);
    assert.ok(res.body.items.every((b) => b.imported));
    // The block still closes the date.
    const q = await h.as("POST", "/api/bookings/quote", { room_id: h.room.id, check_in: D(9), check_out: D(10) });
    assert.equal(q.body.available, false);

    const conflicts = await h.as("GET", "/api/channels/conflicts/list");
    assert.equal(conflicts.body.length, 1);
    assert.equal(conflicts.body[0].overlapping[0].code, own.body.code);
    assert.equal((await h.as("GET", "/api/notifications?kind=sync_conflict")).body.total, 1);
    assert.equal((await h.as("POST", `/api/channels/conflicts/${conflicts.body[0].id}/resolve`, { note: "" })).status, 400);
    assert.equal((await h.as("POST", `/api/channels/conflicts/${conflicts.body[0].id}/resolve`, { note: "Moved own guest to another homestay" })).status, 200);

    // Feed changes: one reservation moved, another removed → updated / cancelled.
    fakes.feeds.set(url, ics([{ uid: "air-1", start: D(6), end: D(8), summary: "Reserved" }]));
    const sync = await h.as("POST", `/api/channels/${c.body.id}/sync`);
    assert.equal(sync.body.updated, 1);
    assert.equal(sync.body.removed, 2);
    const hist = await h.as("GET", `/api/channels/${c.body.id}/history`);
    assert.equal(hist.body.length, 2);

    // Export link: closed nights as VEVENTs, no auth needed.
    const ov = await h.as("GET", "/api/channels");
    const exportUrl = new URL(ov.body.exports[0].url);
    const feed = await call("GET", exportUrl.pathname);
    assert.equal(feed.status, 200);
    assert.match(feed.body, /BEGIN:VCALENDAR/);
    assert.match(feed.body, new RegExp(`DTSTART;VALUE=DATE:${D(2).replaceAll("-", "")}`));
    const regen = await h.as("POST", `/api/channels/exports/${h.room.id}/regenerate`);
    assert.notEqual(regen.body.url, ov.body.exports[0].url);
    assert.equal((await call("GET", exportUrl.pathname)).status, 404, "old link revoked");

    // Broken feed → error status, notification once, backoff; worker retries when due.
    fakes.feeds.delete(url);
    const broken = await h.as("POST", `/api/channels/${c.body.id}/sync`);
    assert.equal(broken.body.ok, false);
    assert.equal(broken.body.connection.status, "error");
    assert.equal((await h.as("GET", "/api/notifications?kind=sync_error")).body.total, 1);
    fakes.feeds.set(url, ics([{ uid: "air-1", start: D(6), end: D(8), summary: "Reserved" }]));
    const conn = await db.findDoc("channel_connections", { id: c.body.id });
    await db.updateDoc("channel_connections", { id: conn.id }, { next_sync_at: new Date(Date.now() - 1000).toISOString() });
    await syncDueConnections(db, fakes.services, fakes.services.fetch);
    assert.equal((await db.findDoc("channel_connections", { id: c.body.id })).status, "active");

    // Disconnect releases future imported dates.
    const del = await h.as("DELETE", `/api/channels/${c.body.id}`);
    assert.equal(del.body.released, 1);
    assert.equal((await h.as("GET", "/api/channels")).body.connections.length, 0);

    // Read-only members can view, not connect.
    const audit = await h.as("GET", "/api/settings/activity?q=calendar");
    assert.ok(audit.body.items.some((a) => a.action === "Connected a calendar"));
  });
});

test("subscription: trial, plans, checkout + invoice, limits, cancel, read-only grace, reminders", async (t) => {
  const fakes = fakeServices();
  const db = memoryDb(t);
  await withServer(db, fakes.services, async (call) => {
    const h = await setupHost(call, fakes, { publish: true, units: 2 });
    let sub = await h.as("GET", "/api/billing");
    assert.equal(sub.body.status, "trialing");
    assert.equal(sub.body.trial_ends_at, D(14));
    assert.equal(sub.body.read_only, false);
    assert.equal(sub.body.usage.units, 2);
    const plans = await h.as("GET", "/api/billing/plans");
    assert.equal(plans.body.trial_days, 14);

    // Quote: 2 units × ₹249 + 18% GST.
    const q = await h.as("POST", "/api/billing/quote", { plan: "starter", interval: "month", units: 2 });
    assert.equal(q.body.total, 587.64);
    assert.equal((await h.as("POST", "/api/billing/checkout", { plan: "starter", interval: "month", units: 1 })).status, 400, "fewer units than in use");

    const co = await h.as("POST", "/api/billing/checkout", { plan: "starter", interval: "month", units: 3 });
    assert.equal(co.status, 201, JSON.stringify(co.body));
    assert.equal((await h.as("POST", `/api/billing/checkout/${co.body.id}/verify`, { test_outcome: "failure" })).status, 402);
    const co2 = await h.as("POST", "/api/billing/checkout", { plan: "starter", interval: "month", units: 3 });
    const paid = await h.as("POST", `/api/billing/checkout/${co2.body.id}/verify`, { test_outcome: "success" });
    assert.equal(paid.status, 200, JSON.stringify(paid.body));
    assert.equal(paid.body.entitlement.status, "active");
    assert.equal(paid.body.entitlement.limits.max_units, 3);
    const inv = await h.as("GET", "/api/billing/invoices");
    assert.equal(inv.body.length, 1);
    assert.match(inv.body[0].number, /^BLB-\d{4}-00001$/);
    const html = await h.as("GET", `/api/billing/invoices/${inv.body[0].id}?format=html`);
    assert.match(html.body, /Tax invoice/);

    // Starter plan: expenses/inbox are Growth features; unit limit enforced.
    assert.equal((await h.as("GET", "/api/expenses")).status, 402);
    const big = await h.as("POST", `/api/properties/${h.prop.id}/rooms`, { name: "Suite", max_adults: 2, unit_count: 2 });
    assert.equal(big.status, 402);
    assert.equal((await h.as("POST", `/api/properties/${h.prop.id}/rooms`, { name: "Suite", max_adults: 2, unit_count: 1 })).status, 201);

    // Cancel → active until period end → resume.
    const cancel = await h.as("POST", "/api/billing/cancel");
    assert.equal(cancel.body.status, "cancelling");
    assert.equal((await h.as("POST", "/api/billing/resume")).body.status, "active");

    // Period ended without payment → read-only grace (writes 402, reads OK), booking page still open.
    const doc = await db.findDoc("subscriptions", { org_id: h.org });
    await db.updateDoc("subscriptions", { id: doc.id }, { current_period_end: D(-2) });
    sub = await h.as("GET", "/api/billing");
    assert.equal(sub.body.status, "grace");
    const blocked = await h.as("POST", "/api/calendar/blocks", { room_ids: [h.room.id], from: D(3), to: D(3) });
    assert.equal(blocked.status, 402);
    assert.equal(blocked.body.code, "subscription_read_only");
    assert.equal((await h.as("GET", "/api/bookings")).status, 200);
    assert.equal((await call("GET", `/api/public/stays/${h.slug}`)).body.booking_mode, "request");
    await billingReminders(db, fakes.services);
    await billingReminders(db, fakes.services);
    assert.equal((await h.as("GET", "/api/notifications?kind=subscription")).body.items.filter((n) => /read-only/.test(n.title)).length, 1, "reminder sent once");

    // Past grace → expired; booking page closed.
    await db.updateDoc("subscriptions", { id: doc.id }, { current_period_end: D(-10) });
    assert.equal((await h.as("GET", "/api/billing")).body.status, "expired");
    assert.equal((await call("GET", `/api/public/stays/${h.slug}`)).body.booking_mode, "closed");
    assert.equal((await call("POST", `/api/public/stays/${h.slug}/book`, { body: { room_id: h.room.id, check_in: D(3), check_out: D(4), guest: { name: "X Y", phone: "+91 98111 11111" } } })).status, 403);

    // Renewing reactivates.
    const co3 = await h.as("POST", "/api/billing/checkout", { plan: "growth", interval: "year", units: 3 });
    const re = await h.as("POST", `/api/billing/checkout/${co3.body.id}/verify`, { test_outcome: "success" });
    assert.equal(re.body.entitlement.status, "active");
    assert.equal((await h.as("GET", "/api/expenses")).status, 200);
  });
});

test("settings: organisation, preferences, sessions sign-out, roles", async (t) => {
  const fakes = fakeServices();
  await withServer(memoryDb(t), fakes.services, async (call) => {
    const h = await setupHost(call, fakes, { publish: false });
    let s = await h.as("GET", "/api/settings");
    assert.equal(s.status, 200);
    assert.equal(s.body.preferences.check_in_time, "13:00");
    assert.equal(s.body.payment_gateway.provider, "none");

    assert.equal((await h.as("PATCH", "/api/settings/organization", { gstin: "BAD" })).status, 400);
    const org = await h.as("PATCH", "/api/settings/organization", {
      name: "Asha Stays", legal_name: "Asha Stays LLP", contact_email: "hello@ashastays.example", gstin: "29ABCDE1234F1Z5",
      address: { line: "Mall Road", city: "Manali", state: "HP", postal_code: "175131" },
    });
    assert.equal(org.status, 200, JSON.stringify(org.body));
    assert.equal(org.body.name, "Asha Stays");
    assert.match(org.body.address, /Manali/);
    assert.equal((await h.as("PATCH", "/api/settings/preferences", { check_in_time: "25:00" })).status, 400);
    const prefs = await h.as("PATCH", "/api/settings/preferences", { check_in_time: "14:00", tax_percent: 12, cancellation_policy: "moderate" });
    assert.equal(prefs.body.tax_percent, 12);

    // Sessions: a second sign-in, signed out from the first device.
    await call("POST", "/api/auth/login/request-otp", { body: { identifier: "asha@example.com" } });
    const second = await call("POST", "/api/auth/login/verify-otp", { body: { identifier: "asha@example.com", code: codeFrom(fakes.mail) } });
    assert.equal(second.status, 200, JSON.stringify(second.body));
    const sessions = await h.as("GET", "/api/account/sessions");
    assert.equal(sessions.body.length, 2);
    assert.equal(sessions.body.filter((x) => x.current).length, 1);
    const other = sessions.body.find((x) => !x.current);
    await h.as("DELETE", `/api/account/sessions/${other.id}`);
    assert.equal((await call("GET", "/api/auth/me", { token: second.body.access_token })).status, 401);
    assert.equal((await call("GET", "/api/auth/me", { token: h.token })).status, 200);

    // Activity log records who changed what.
    const act = await h.as("GET", "/api/settings/activity");
    assert.ok(act.body.items.some((a) => a.action === "Updated organisation details" && a.user_name === "Asha Host"));
    assert.ok(act.body.items.some((a) => a.action === "Created a property"));
  });
});
