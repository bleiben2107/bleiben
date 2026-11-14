import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { createApp } from "../src/app.js";
import { addDays, todayStr } from "../src/bookings/core.js";
import { createDb } from "../src/db.js";
import { dispatchScheduled } from "../src/routes/messages.js";

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

async function signUp(call, fakes, name, email) {
  await call("POST", "/api/auth/signup/request-otp", { body: { name, email } });
  const v = await call("POST", "/api/auth/signup/verify-otp", { body: { email, code: codeFrom(fakes.mail) } });
  assert.equal(v.status, 201, JSON.stringify(v.body));
  return v.body;
}

const D = (n) => addDays(todayStr(), n);

test("inbox: threads per booking, log + reply, templates, flags per user, note, scheduled (held on change), reply times", async (t) => {
  const fakes = fakeServices();
  const db = memoryDb(t);
  await withServer(db, fakes.services, async (call) => {
    const owner = await signUp(call, fakes, "Asha Host", "asha@example.com");
    const token = owner.access_token;
    const org = owner.memberships[0].org_id;
    const as = (method, path, body) => call(method, path, { token, org, body });
    const prop = await as("POST", "/api/properties", {
      title: "Pine Cottage", base_price: 4000, check_in_time: "1 PM", checkInTime: "1 PM", address: { city: "Manali" },
    });
    const room = await as("POST", `/api/properties/${prop.body.id}/rooms`, { name: "Deluxe", max_adults: 2, unit_count: 1 });
    const b = await as("POST", "/api/bookings", {
      room_id: room.body.id, check_in: D(5), check_out: D(7), guest: { name: "Ravi Kumar", phone: "+91 98111 11111" }, source: "airbnb", confirm: true,
    });
    assert.equal(b.status, 201, JSON.stringify(b.body));

    // A conversation appears for the booking.
    let list = await as("GET", "/api/messages");
    assert.equal(list.status, 200, JSON.stringify(list.body));
    assert.equal(list.body.total, 1);
    const th = list.body.items[0];
    assert.equal(th.guest_name, "Ravi Kumar");
    assert.equal(th.channel_label, "Airbnb");
    assert.equal(th.stage, "upcoming");
    assert.equal(th.unread, false);

    // Log a guest message → unread + waiting on you.
    const inMsg = await as("POST", `/api/messages/${th.id}/messages`, { direction: "in", body: "Can we check in early?" });
    assert.equal(inMsg.status, 201);
    list = await as("GET", "/api/messages?unread=true");
    assert.equal(list.body.total, 1);
    assert.ok(list.body.items[0].waiting_since);
    assert.equal((await as("GET", "/api/messages/unread-count")).body.count, 1);

    // Reply with template variables filled in; replying marks it read.
    const out = await as("POST", `/api/messages/${th.id}/messages`, { body: "Hi {guest_first_name}, {property_name} check-in is {check_in} for {nights} nights." });
    assert.equal(out.status, 201);
    assert.match(out.body.message.body, /^Hi Ravi, Pine Cottage check-in is \d+ \w+ \d{4} for 2 nights\.$/);
    assert.equal((await as("GET", "/api/messages/unread-count")).body.count, 0);

    // Quick replies: starters + own, shortcut uniqueness.
    const qr = await as("GET", "/api/messages/quick-replies");
    assert.ok(qr.body.starter.some((r) => r.shortcut === "early"));
    assert.equal((await as("POST", "/api/messages/quick-replies", { shortcut: "early", title: "x", body: "y" })).status, 400);
    const mine = await as("POST", "/api/messages/quick-replies", { shortcut: "wifi", title: "Wi-Fi", body: "Wi-Fi is PineGuest" });
    assert.equal(mine.status, 201);
    const rendered = await as("POST", `/api/messages/${th.id}/render`, { body: "{nearest_free_dates}" });
    assert.match(rendered.body.body, /–/);

    // Search (2+ letters), filters
    assert.equal((await as("GET", "/api/messages?q=early")).body.total, 1);
    assert.equal((await as("GET", "/api/messages?q=zzz")).body.total, 0);
    assert.equal((await as("GET", "/api/messages?channel=phone")).body.total, 0);
    assert.equal((await as("GET", "/api/messages?stage=upcoming")).body.total, 1);

    // Star / archive are per user.
    await as("POST", `/api/messages/${th.id}/state`, { starred: true, archived: true });
    assert.equal((await as("GET", "/api/messages")).body.total, 0);
    assert.equal((await as("GET", "/api/messages?view=archived")).body.items[0].starred, true);
    await as("POST", `/api/messages/${th.id}/state`, { archived: false });

    // Team note
    const note = await as("PUT", `/api/messages/${th.id}/note`, { text: "VIP guest" });
    assert.equal(note.body.note.edited_by, "Asha Host");

    // Scheduled: too soon refused; due message sends; another is held when the booking changes.
    assert.equal((await as("POST", `/api/messages/${th.id}/scheduled`, { body: "x", send_at: new Date().toISOString() })).status, 400);
    const later = new Date(Date.now() + 2 * 3600_000).toISOString();
    const s1 = await as("POST", `/api/messages/${th.id}/scheduled`, { body: "See you on {check_in}", send_at: later });
    assert.equal(s1.status, 201, JSON.stringify(s1.body));
    const s2 = await as("POST", `/api/messages/${th.id}/scheduled`, { body: "Reminder", send_at: later });
    const sent = await as("POST", `/api/messages/${th.id}/scheduled/${s1.body.id}/send-now`);
    assert.equal(sent.body.status, "sent");
    // Booking dates change → the remaining one is held, not sent.
    await as("PATCH", `/api/bookings/${b.body.id}`, { check_in: D(6), check_out: D(8) });
    await dispatchScheduled(db, new Date(Date.now() + 3 * 3600_000).toISOString());
    let detail = await as("GET", `/api/messages/${th.id}`);
    const held = detail.body.scheduled.find((x) => x.id === s2.body.id);
    assert.equal(held.status, "held");
    assert.match(held.held_reason, /changed/);
    assert.equal(detail.body.messages.filter((m) => m.direction === "out").length, 2);
    assert.equal(detail.body.note.text, "VIP guest");
    assert.ok(detail.body.details.payout_note);
    assert.ok(detail.body.property_info.some((p) => p.label === "Check-in time"));
    // Cancel the held one
    assert.equal((await as("DELETE", `/api/messages/${th.id}/scheduled/${s2.body.id}`)).status, 200);

    // Reply times
    const rt = await as("GET", "/api/messages/reply-times?range=today");
    assert.equal(rt.body.replies, 1);
    assert.equal(rt.body.within_hour, 100);
    assert.equal(rt.body.by_agent[0].agent, "Asha Host");

    // Other orgs can't open it
    const other = await signUp(call, fakes, "Other Host", "other@example.com");
    assert.equal((await call("GET", `/api/messages/${th.id}`, { token: other.access_token, org: other.memberships[0].org_id })).status, 404);
  });
});
