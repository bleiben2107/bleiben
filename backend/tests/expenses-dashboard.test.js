import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { createApp } from "../src/app.js";
import { addDays, todayStr } from "../src/bookings/core.js";
import { createDb } from "../src/db.js";

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
const monthAdd = (month, n) => {
  const [y, m] = month.split("-").map(Number);
  const d = new Date(Date.UTC(y, m - 1 + n, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
};

test("expenses: entries with lines, filters, monthly repeats (auto-file, skip, edit ahead, stop), export", async (t) => {
  const fakes = fakeServices();
  await withServer(memoryDb(t), fakes.services, async (call) => {
    const owner = await signUp(call, fakes, "Asha Host", "asha@example.com");
    const token = owner.access_token;
    const org = owner.memberships[0].org_id;
    const as = (method, path, body) => call(method, path, { token, org, body });
    const prop = await as("POST", "/api/properties", { title: "Pine Cottage", address: { city: "Manali" } });
    const P = prop.body.id;

    const meta = await as("GET", "/api/expenses/meta");
    assert.equal(meta.body.categories.length, 17);

    // Validation
    assert.equal((await as("POST", "/api/expenses", { property_id: P, date: D(0), lines: [] })).status, 400);
    assert.equal((await as("POST", "/api/expenses", { property_id: P, date: D(3), lines: [{ category: "Rent", amount: 1 }] })).status, 400);
    assert.equal((await as("POST", "/api/expenses", { property_id: P, date: D(0), lines: [{ category: "Nope", amount: 1 }] })).status, 400);

    // One entry, two lines
    const e1 = await as("POST", "/api/expenses", {
      property_id: P,
      date: D(0),
      payment_mode: "upi",
      notes: "Weekly",
      lines: [{ category: "Laundry", amount: 1200 }, { category: "Supplies & toiletries", amount: 800, note: "Soap" }],
    });
    assert.equal(e1.status, 201, JSON.stringify(e1.body));
    assert.equal(e1.body.total, 2000);
    assert.equal(e1.body.added_by, "Asha Host");

    // Repeating rent from two months ago → last month and this month auto-file.
    const today = todayStr();
    const thisMonth = today.slice(0, 7);
    const start = monthAdd(thisMonth, -2);
    const rent = await as("POST", "/api/expenses", {
      property_id: P,
      date: `${start}-05`,
      payment_mode: "bank_transfer",
      lines: [{ category: "Rent", amount: 30000, repeat_monthly: true }],
    });
    assert.equal(rent.status, 201, JSON.stringify(rent.body));
    assert.equal(rent.body.repeats_monthly, true);
    const ruleId = rent.body.lines[0].rule_id;
    let list = await as("GET", "/api/expenses?recurring=true&page_size=100");
    assert.equal(list.body.total, 3);
    assert.equal(list.body.items.filter((i) => i.auto_filed).length, 2);
    list = await as("GET", "/api/expenses?recurring=true");
    assert.equal(list.body.total, 3, "filing is idempotent");

    // Filters: category, mode, amount over/under (entry total), search, period
    assert.equal((await as("GET", "/api/expenses?category=Laundry")).body.total, 1);
    assert.equal((await as("GET", "/api/expenses?payment_mode=upi")).body.total, 1);
    assert.equal((await as("GET", "/api/expenses?min=25000")).body.total, 3);
    assert.equal((await as("GET", "/api/expenses?max=2000")).body.total, 1);
    assert.equal((await as("GET", "/api/expenses?q=soap")).body.total, 1);
    assert.ok((await as("GET", `/api/expenses?from=${today}&to=${today}`)).body.items.some((i) => i.id === e1.body.id));

    // Skip this month: kept at ₹0, undoable
    let r = await as("POST", `/api/expenses/rules/${ruleId}/skip`, { month: thisMonth, reason: "Owner waived" });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    const cur = (await as("GET", "/api/expenses?recurring=true")).body.items.find((i) => i.date.startsWith(thisMonth));
    assert.equal(cur.total, 0);
    assert.equal(cur.skipped, true);
    await as("POST", `/api/expenses/rules/${ruleId}/unskip`, { month: thisMonth });
    assert.equal((await as("GET", `/api/expenses/${cur.id}`)).body.total, 30000);

    // A repeating line can't be removed from one month alone; its amount can change.
    assert.equal((await as("PATCH", `/api/expenses/${cur.id}`, { lines: [{ category: "Other", amount: 5 }] })).status, 400);
    const ok = await as("PATCH", `/api/expenses/${cur.id}`, { lines: [{ index: 0, category: "Rent", amount: 31000 }] });
    assert.equal(ok.body.total, 31000);

    // Edit amount ahead: filed months unchanged
    r = await as("PATCH", `/api/expenses/rules/${ruleId}`, { amount: 35000 });
    assert.match(r.body.message, /Months already filed are unchanged/);
    const filed = (await as("GET", "/api/expenses?recurring=true")).body.items.map((i) => i.total).sort();
    assert.deepEqual(filed, [30000, 30000, 31000]);
    const next = r.body.schedule.find((s) => s.month === monthAdd(thisMonth, 1));
    assert.equal(next.amount, 35000);
    assert.equal(next.status, "upcoming");

    // Skipping every upcoming month warns that nothing will file
    for (const m of [1, 2, 3]) r = await as("POST", `/api/expenses/rules/${ruleId}/skip`, { month: monthAdd(thisMonth, m) });
    assert.match(r.body.message, /Nothing will file/);

    // Stop: status stopped, editing refused
    r = await as("POST", `/api/expenses/rules/${ruleId}/stop`);
    assert.equal(r.body.status, "stopped");
    assert.equal((await as("PATCH", `/api/expenses/rules/${ruleId}`, { amount: 1 })).status, 400);

    // Deleting a filed month removes only that month and it isn't re-filed
    const first = (await as("GET", "/api/expenses?recurring=true&sort=date_asc")).body.items[0];
    assert.equal((await as("DELETE", `/api/expenses/${first.id}`)).status, 200);
    assert.equal((await as("GET", "/api/expenses?recurring=true")).body.total, 2);

    // Export CSV (one row per line) and empty export
    const csv = await as("GET", "/api/expenses/export");
    assert.equal(csv.status, 200);
    assert.match(csv.headers.get("content-type"), /text\/csv/);
    assert.equal(csv.body.split("\n").length, 1 + 2 + 2);
    assert.equal((await as("GET", "/api/expenses/export?category=Insurance")).status, 400);

    // Attachments must be uploaded first
    const att = await as("POST", "/api/expenses", { property_id: P, date: D(0), lines: [{ category: "Other", amount: 1 }], attachments: ["http://x/y.png"] });
    assert.equal(att.status, 400);

    // Other orgs can't see entries
    const other = await signUp(call, fakes, "Other Host", "other@example.com");
    const theirs = await call("GET", `/api/expenses/${e1.body.id}`, { token: other.access_token, org: other.memberships[0].org_id });
    assert.equal(theirs.status, 404);
  });
});

test("dashboard: KPIs with comparison, today, sources, money, ranking, monthly, outlook, alerts", async (t) => {
  const fakes = fakeServices();
  await withServer(memoryDb(t), fakes.services, async (call) => {
    const owner = await signUp(call, fakes, "Asha Host", "asha@example.com");
    const token = owner.access_token;
    const org = owner.memberships[0].org_id;
    const as = (method, path, body) => call(method, path, { token, org, body });
    const prop = await as("POST", "/api/properties", { title: "Pine Cottage", base_price: 4000, address: { city: "Manali" } });
    const room = await as("POST", `/api/properties/${prop.body.id}/rooms`, { name: "Deluxe", max_adults: 2, unit_count: 1 });
    const R = room.body.id;
    const guest = { name: "Ravi", phone: "+91 98111 11111" };

    // Checked-in stay from today (2 nights, direct, paid) and a phone booking right after (unpaid)
    const b1 = await as("POST", "/api/bookings", { room_id: R, check_in: D(0), check_out: D(2), guest, source: "direct", payment: { amount: 8000, method: "upi" } });
    assert.equal(b1.status, 201, JSON.stringify(b1.body));
    await as("POST", `/api/bookings/${b1.body.id}/check-in`);
    const b2 = await as("POST", "/api/bookings", { room_id: R, check_in: D(2), check_out: D(3), guest, source: "phone" });
    assert.equal(b2.body.status, "pending_payment");
    await as("POST", "/api/expenses", { property_id: prop.body.id, date: D(0), lines: [{ category: "Laundry", amount: 1000 }, { category: "Rent", amount: 3000 }] });

    const d = await as("GET", "/api/dashboard?period=next_7");
    assert.equal(d.status, 200, JSON.stringify(d.body));
    const k = d.body.kpis;
    assert.equal(d.body.range.days, 7);
    assert.equal(k.revenue.value, 12000);
    assert.equal(k.expenses.value, 4000);
    assert.equal(k.noi.value, 8000);
    assert.equal(k.noi.margin, 66.7);
    assert.equal(k.occupancy.booked_nights, 3);
    assert.equal(k.occupancy.available_nights, 7);
    assert.equal(k.adr.value, 4000);
    assert.equal(k.revenue.change, null, "nothing in the previous period");
    assert.equal(d.body.today_panel.check_ins.count, 1);
    assert.equal(d.body.today_panel.ongoing.count, 1);
    assert.equal(d.body.today_panel.arriving_soon.count, 1);
    assert.equal(d.body.sources.length, 2);
    assert.equal(d.body.sources.find((s) => s.source === "direct").saved_commission, 1200);
    assert.deepEqual(d.body.money.map((m) => m.category), ["Rent", "Laundry"]);
    assert.equal(d.body.money[0].share, 75);
    assert.equal(d.body.properties[0].revenue, 12000);
    assert.equal(d.body.monthly.months.length, 12);
    assert.equal(d.body.outlook.length, 13);
    assert.equal(d.body.outlook[0].booked_nights, 3);
    assert.ok(d.body.alerts.some((a) => a.kind === "balance_due"));

    // Count by booking date over the last 30 days sees both bookings
    const byBooked = await as("GET", "/api/dashboard?period=last_30&count_by=booked");
    assert.equal(byBooked.body.kpis.bookings.value, 2);

    // Cancelling the unpaid booking removes its revenue
    await as("POST", `/api/bookings/${b2.body.id}/cancel`, { reason: "Guest changed plans" });
    const after = await as("GET", "/api/dashboard?period=next_7");
    assert.equal(after.body.kpis.revenue.value, 8000);

    // Blocking every night of week 2 makes it "not offered"
    await as("POST", "/api/calendar/blocks", { room_ids: [R], from: D(7), to: D(13), reason: "Maintenance" });
    const blocked = await as("GET", "/api/dashboard?period=next_7");
    assert.equal(blocked.body.outlook[1].band, "not_offered");

    assert.equal((await as("GET", "/api/dashboard?period=custom&from=2026-01-10&to=2026-01-01")).status, 400);
    assert.equal((await as("GET", "/api/dashboard?property_id=999999")).body.totals.properties, 0);
  });
});
