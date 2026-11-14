import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { createApp } from "../src/app.js";
import { addDays, todayStr } from "../src/bookings/core.js";
import { createDb } from "../src/db.js";
import { expireHolds } from "../src/routes/bookings.js";

function memoryDb(t) {
  const filePath = `./data/test-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.json`;
  t.after(() => fs.rmSync(filePath, { force: true }));
  return createDb(filePath);
}

function fakeServices() {
  const mail = [];
  return {
    mail,
    services: {
      mailer: { configured: true, send: async (m) => (mail.push(m), { delivered: true }) },
      sms: { configured: true, send: async () => ({ delivered: true }) },
    },
  };
}

async function withServer(db, services, run) {
  const app = createApp(db, services);
  const server = app.listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, { token, body, org } = {}) => {
    const headers = { "Content-Type": "application/json" };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (org) headers["X-Org-Id"] = String(org);
    const res = await fetch(`${base}${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
    const text = await res.text();
    let parsed = text;
    try {
      parsed = text ? JSON.parse(text) : null;
    } catch {
      /* csv */
    }
    return { status: res.status, body: parsed, headers: res.headers };
  };
  try {
    await run(call);
  } finally {
    await new Promise((r) => server.close(r));
  }
}

const codeFrom = (list) => (list.at(-1).text.match(/\d{6}/) ?? [])[0];

async function signUp(call, fakes, name, email, inviteToken) {
  await call("POST", "/api/auth/signup/request-otp", { body: { name, email } });
  const v = await call("POST", "/api/auth/signup/verify-otp", { body: { email, code: codeFrom(fakes.mail), invite_token: inviteToken } });
  assert.equal(v.status, 201, JSON.stringify(v.body));
  return v.body;
}

const D = (n) => addDays(todayStr(), n);

test("calendar + bookings engine: blocks, pricing, quotes, overlap, holds, payments, lifecycle", async (t) => {
  const fakes = fakeServices();
  await withServer(memoryDb(t), fakes.services, async (call) => {
    const owner = await signUp(call, fakes, "Asha Host", "asha@example.com");
    const token = owner.access_token;
    const org = owner.memberships[0].org_id;
    const as = (method, path, body) => call(method, path, { token, org, body });

    const prop = await as("POST", "/api/properties", { title: "Pine Cottage", base_price: 4000, address: { city: "Manali" } });
    const deluxe = await as("POST", `/api/properties/${prop.body.id}/rooms`, { name: "Deluxe", max_adults: 2, max_children: 1, unit_count: 2, extra_guest_charge: 500 });
    const suite = await as("POST", `/api/properties/${prop.body.id}/rooms`, { name: "Suite", max_adults: 4, unit_count: 1, base_price: 9000 });
    const R = deluxe.body.id;
    const S = suite.body.id;

    // Calendar grid
    const cal = await as("GET", `/api/calendar?from=${D(1)}&days=5`);
    assert.equal(cal.status, 200, JSON.stringify(cal.body));
    assert.equal(cal.body.days.length, 5);
    const row = cal.body.properties[0].rooms.find((r) => r.id === R);
    assert.equal(row.cells[0].price, 4000);
    assert.equal(row.cells[0].available, 2);

    // Block / unblock with reason, weekday filter
    const blk = await as("POST", "/api/calendar/blocks", { room_ids: [R], from: D(2), to: D(2), reason: "Maintenance", notes: "Painting" });
    assert.equal(blk.status, 201);
    let cells = (await as("GET", `/api/calendar?from=${D(1)}&days=5`)).body.properties[0].rooms.find((r) => r.id === R).cells;
    assert.equal(cells[1].blocked, true);
    assert.equal(cells[1].available, 0);
    assert.equal(cells[1].block_reason, "Maintenance");
    await as("PATCH", "/api/calendar/blocks", { room_ids: [R], from: D(2), reason: "Owner stay" });
    cells = (await as("GET", `/api/calendar?from=${D(1)}&days=5`)).body.properties[0].rooms.find((r) => r.id === R).cells;
    assert.equal(cells[1].block_reason, "Owner stay");

    // A stay across the blocked night is refused with the conflicting date.
    const blockedQuote = await as("POST", "/api/bookings/quote", { room_id: R, check_in: D(1), check_out: D(3) });
    assert.equal(blockedQuote.body.available, false);
    assert.equal(blockedQuote.body.conflicts[0].date, D(2));
    const opened = await as("POST", "/api/calendar/unblock", { room_ids: [R], from: D(2), to: D(2) });
    assert.equal(opened.body.opened, 1);

    // Pricing: fixed price, then +10% (Flexi Pricing)
    const set = await as("PUT", "/api/calendar/rates", { room_ids: [R], from: D(3), to: D(3), price: 5000 });
    assert.equal(set.body.updated, 1);
    const pct = await as("PUT", "/api/calendar/rates", { room_ids: [R], from: D(4), to: D(4), percent: 10 });
    assert.equal(pct.body.updated, 1);
    const both = await as("PUT", "/api/calendar/rates", { room_ids: [R], from: D(4), price: 1, percent: 5 });
    assert.equal(both.status, 400);
    cells = (await as("GET", `/api/calendar?from=${D(1)}&days=5`)).body.properties[0].rooms.find((r) => r.id === R).cells;
    assert.equal(cells[2].price, 5000);
    assert.equal(cells[3].price, 4400);

    // Quote: nights D1..D4 = 4000 + 4000 + 5000; 3 guests on a 2-adult room → 1 extra × 500 × 3
    const q = await as("POST", "/api/bookings/quote", { room_id: R, check_in: D(1), check_out: D(4), adults: 2, children: 1 });
    assert.equal(q.body.available, true);
    assert.equal(q.body.stay, 13000);
    assert.equal(q.body.extra_guest_charge, 1500);
    assert.equal(q.body.total, 14500);

    // Create: validation, advance payment → confirmed
    const noGuest = await as("POST", "/api/bookings", { room_id: R, check_in: D(1), check_out: D(3) });
    assert.equal(noGuest.status, 400);
    const guest = { name: "Ravi Kumar", phone: "+91 98111 11111" };
    const b1 = await as("POST", "/api/bookings", {
      room_id: R, check_in: D(1), check_out: D(3), guest, adults: 2, source: "phone", payment: { amount: 3000, method: "upi" },
    });
    assert.equal(b1.status, 201, JSON.stringify(b1.body));
    assert.equal(b1.body.status, "confirmed");
    assert.equal(b1.body.total, 8000);
    assert.equal(b1.body.paid, 3000);
    assert.equal(b1.body.balance, 5000);
    assert.equal(b1.body.payment_status, "partial");
    assert.match(b1.body.code, /^BLB-[0-9A-F]{6}$/);

    // Second unit, then the room is full for those nights
    const b2 = await as("POST", "/api/bookings", { room_id: R, check_in: D(2), check_out: D(3), guest: { name: "Meena", email: "meena@x.in" } });
    assert.equal(b2.body.status, "pending_payment");
    const full = await as("POST", "/api/bookings", { room_id: R, check_in: D(2), check_out: D(4), guest });
    assert.equal(full.status, 409);
    assert.equal(full.body.conflicts[0].date, D(2));

    // Overlap prevention under concurrency: one unit left, two simultaneous requests
    const race = await Promise.all([1, 2].map((i) =>
      as("POST", "/api/bookings", { room_id: S, check_in: D(5), check_out: D(7), guest: { name: `Racer ${i}`, phone: "9000000000" } })));
    assert.deepEqual(race.map((r) => r.status).sort(), [201, 409]);

    // Hold takes the unit for 15 minutes, then expires and frees it
    const hold = await as("POST", "/api/bookings", { room_id: S, check_in: D(8), check_out: D(9), guest, hold: true });
    assert.equal(hold.body.status, "held");
    assert.ok(hold.body.hold_expires_at);
    const blockedByHold = await as("POST", "/api/bookings/quote", { room_id: S, check_in: D(8), check_out: D(9) });
    assert.equal(blockedByHold.body.available, false);
    // (Expiry itself is covered by "expired holds are released" below.)
    const list1 = await as("GET", "/api/bookings?tab=all");
    assert.ok(list1.body.items.some((i) => i.status === "held"));

    // Payments: balance clears, overpay refused, refund
    const over = await as("POST", `/api/bookings/${b1.body.id}/payments`, { amount: 6000, method: "cash" });
    assert.equal(over.status, 400);
    const rest = await as("POST", `/api/bookings/${b1.body.id}/payments`, { amount: 5000, method: "cash" });
    assert.equal(rest.body.payment_status, "paid");
    assert.equal(rest.body.balance, 0);
    const pay2 = await as("POST", `/api/bookings/${b2.body.id}/payments`, { amount: 1000, method: "card" });
    assert.equal(pay2.body.status, "confirmed", "a payment confirms a pending booking");

    // Lifecycle: check-in → check-out; invalid transitions refused
    const badOut = await as("POST", `/api/bookings/${b1.body.id}/check-out`);
    assert.equal(badOut.status, 409);
    assert.equal((await as("POST", `/api/bookings/${b1.body.id}/check-in`)).body.status, "checked_in");
    assert.equal((await as("POST", `/api/bookings/${b1.body.id}/check-out`)).body.status, "checked_out");
    const editDone = await as("PATCH", `/api/bookings/${b1.body.id}`, { notes: "x" });
    assert.equal(editDone.status, 409);

    // Edit: move b2 to free dates (re-priced), guest details
    const moved = await as("PATCH", `/api/bookings/${b2.body.id}`, { check_in: D(10), check_out: D(12), guest: { phone: "9822222222" } });
    assert.equal(moved.status, 200, JSON.stringify(moved.body));
    assert.equal(moved.body.check_in, D(10));
    assert.equal(moved.body.total, 8000);
    assert.equal(moved.body.guest.phone, "9822222222");

    // Cancel needs a reason and frees inventory
    const noReason = await as("POST", `/api/bookings/${b2.body.id}/cancel`, {});
    assert.equal(noReason.status, 400);
    const cancelled = await as("POST", `/api/bookings/${b2.body.id}/cancel`, { reason: "Guest changed plans" });
    assert.equal(cancelled.body.status, "cancelled");
    assert.equal(cancelled.body.trip_status, "cancelled");
    const freeAgain = await as("POST", "/api/bookings/quote", { room_id: R, check_in: D(10), check_out: D(12) });
    assert.equal(freeAgain.body.available, true);
    assert.ok(cancelled.body.events.some((e) => e.action === "cancelled"));

    // List: tabs, counts, search, export
    const list = await as("GET", "/api/bookings?tab=cancelled");
    assert.equal(list.body.total, 1);
    assert.ok(list.body.counts.all >= 4);
    const search = await as("GET", "/api/bookings?q=ravi");
    assert.ok(search.body.items.every((i) => i.guest.name === "Ravi Kumar"));
    const csv = await as("GET", "/api/bookings/export");
    assert.equal(csv.status, 200);
    assert.match(csv.body, /^"Booking ID","Status","Source"/);

    // Isolation and roles
    const other = await signUp(call, fakes, "Other Host", "other@example.com");
    const peek = await call("GET", `/api/bookings/${b1.body.id}`, { token: other.access_token, org: other.memberships[0].org_id });
    assert.equal(peek.status, 404);
    const otherCal = await call("POST", "/api/calendar/blocks", { token: other.access_token, org: other.memberships[0].org_id, body: { room_ids: [R], from: D(1) } });
    assert.equal(otherCal.status, 404);

    await call("POST", `/api/orgs/${org}/invites`, { token, body: { email: "viewer@example.com", role: "read_only" } });
    const invite = decodeURIComponent(fakes.mail.at(-1).text.match(/invite_token=(\S+)/)[1]);
    const viewer = await signUp(call, fakes, "View Er", "viewer@example.com", invite);
    const vRead = await call("GET", "/api/calendar", { token: viewer.access_token, org });
    assert.equal(vRead.status, 200);
    const vWrite = await call("POST", "/api/bookings", { token: viewer.access_token, org, body: { room_id: R, check_in: D(20), check_out: D(21), guest } });
    assert.equal(vWrite.status, 403);
  });
});

test("expired holds are released", async (t) => {
  const db = memoryDb(t);
  const past = new Date(Date.now() - 60000).toISOString();
  await db.insertDoc("bookings", { org_id: 1, room_id: 1, status: "held", hold_expires_at: past, check_in: D(1), check_out: D(2), events: [] });
  await db.insertDoc("bookings", { org_id: 1, room_id: 1, status: "held", hold_expires_at: new Date(Date.now() + 600000).toISOString(), check_in: D(1), check_out: D(2), events: [] });
  assert.equal(await expireHolds(db), 1);
  const statuses = (await db.findDocs("bookings", { org_id: 1 })).map((b) => b.status).sort();
  assert.deepEqual(statuses, ["expired", "held"]);
});
