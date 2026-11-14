import { Router } from "express";

import { DATE_RE, InputError, nowIso, todayStr } from "../bookings/core.js";
import { savePhoto } from "../uploads.js";

/**
 * Expenses (REA 08 §4): an entry groups expense lines (category + amount) for
 * one property and date. A line can repeat monthly: that creates a rule which
 * files the line automatically each month ("Auto-filed"), can skip a month
 * (kept at ₹0, undoable), takes new amounts for the months ahead only, and
 * can be stopped (upcoming months are no longer filed).
 */

export const EXPENSE_CATEGORIES = [
  "Rent",
  "Staff salary",
  "Housekeeping & cleaning",
  "Laundry",
  "Electricity",
  "Water",
  "Gas",
  "Internet & TV",
  "Repairs & maintenance",
  "Supplies & toiletries",
  "Food & kitchen",
  "OTA commission & fees",
  "Marketing",
  "Software & subscriptions",
  "Taxes & licences",
  "Insurance",
  "Other",
];

export const EXPENSE_MODES = ["cash", "upi", "card", "bank_transfer", "cheque", "other"];
const MODE_LABELS = { cash: "Cash", upi: "UPI", card: "Card", bank_transfer: "Bank transfer", cheque: "Cheque", other: "Other" };

export const EXPORT_MAX = 5000;
const MONTH_RE = /^\d{4}-\d{2}$/;

const handle = (fn) => async (req, res, next) => {
  try {
    if (req.scope?.org_id == null) throw new InputError("Choose an organisation (X-Org-Id) first");
    return await fn(req, res);
  } catch (err) {
    if (err instanceof InputError) return res.status(err.status).json({ detail: err.message, ...err.extra });
    return next(err);
  }
};

const round2 = (n) => Math.round(n * 100) / 100;
const monthOf = (date) => date.slice(0, 7);
const addMonths = (month, n) => {
  const [y, m] = month.split("-").map(Number);
  const d = new Date(Date.UTC(y, m - 1 + n, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
};
const daysIn = (month) => {
  const [y, m] = month.split("-").map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
};
const dateFor = (month, day) => `${month}-${String(Math.min(day, daysIn(month))).padStart(2, "0")}`;
const byName = (req) => req.user.name || req.user.email || `user ${req.user.id}`;

function validLine(l, i) {
  const category = String(l?.category ?? "").trim();
  if (!EXPENSE_CATEGORIES.includes(category)) throw new InputError(`Line ${i + 1}: choose a category`);
  const amount = Number(l?.amount);
  if (!Number.isFinite(amount) || amount < 0 || amount > 1e8) throw new InputError(`Line ${i + 1}: enter an amount of ₹0 or more`);
  return { category, amount: round2(amount), note: String(l?.note ?? "").trim().slice(0, 200) };
}

async function orgProperty(db, orgId, id) {
  const p = await db.findDoc("properties", { id: Number(id) });
  if (!p || p.org_id !== orgId || p.status === "deleted") throw new InputError("Property not found", 404);
  return p;
}

const totalOf = (lines) => round2(lines.reduce((s, l) => s + (l.skipped ? 0 : l.amount), 0));

/**
 * Files every month a rule owes, up to the current month (idempotent).
 * A skipped month is filed at ₹0 and marked Skipped.
 */
export async function fileRecurring(db, orgId) {
  const now = monthOf(todayStr());
  const rules = (await db.findDocs("expense_rules", { org_id: orgId })).filter((r) => r.status === "active" || r.end_month);
  if (!rules.length) return 0;
  const entries = await db.findDocs("expenses", { org_id: orgId });
  const filed = new Set();
  for (const e of entries) for (const l of e.lines) if (l.rule_id) filed.add(`${l.rule_id}:${monthOf(e.date)}`);
  let n = 0;
  for (const r of rules) {
    const last = r.end_month && r.end_month < now ? r.end_month : now;
    for (let m = r.start_month; m <= last; m = addMonths(m, 1)) {
      if (filed.has(`${r.id}:${m}`) || r.removed?.includes(m)) continue;
      const skipped = Object.hasOwn(r.skips ?? {}, m);
      const amount = r.amounts?.[m] ?? r.amount;
      const t = nowIso();
      await db.insertDoc("expenses", {
        org_id: orgId,
        property_id: r.property_id,
        date: dateFor(m, r.day),
        payment_mode: r.payment_mode,
        notes: "",
        attachments: [],
        lines: [{ category: r.category, amount, note: r.note ?? "", rule_id: r.id, skipped, skip_reason: skipped ? r.skips[m] : undefined }],
        total: skipped ? 0 : amount,
        auto_filed: true,
        created_by: r.created_by,
        created_by_name: "Auto-filed",
        created_at: t,
        updated_at: t,
      });
      filed.add(`${r.id}:${m}`);
      n++;
    }
  }
  return n;
}

async function publicEntry(db, e, cache = new Map()) {
  if (!cache.has(e.property_id)) cache.set(e.property_id, await db.findDoc("properties", { id: e.property_id }));
  const p = cache.get(e.property_id);
  return {
    id: e.id,
    date: e.date,
    property: { id: e.property_id, title: p?.title || "Untitled property", city: p?.address?.city ?? "" },
    payment_mode: e.payment_mode,
    payment_mode_label: MODE_LABELS[e.payment_mode] ?? e.payment_mode,
    notes: e.notes ?? "",
    attachments: e.attachments ?? [],
    lines: e.lines.map((l, i) => ({ index: i, ...l })),
    total: e.total,
    repeats_monthly: e.lines.some((l) => l.rule_id),
    skipped: e.lines.length > 0 && e.lines.every((l) => l.skipped),
    auto_filed: !!e.auto_filed,
    added_by: e.created_by_name ?? "",
    added_on: e.created_at,
    updated_at: e.updated_at,
  };
}

function publicRule(r, filedMonths = new Set()) {
  const now = monthOf(todayStr());
  const ended = r.status !== "active";
  // Schedule: every month from the start up to 3 months ahead (or the end).
  const until = ended ? r.end_month ?? r.start_month : addMonths(now, 3);
  const schedule = [];
  for (let m = r.start_month; m <= until; m = addMonths(m, 1)) {
    const skipped = Object.hasOwn(r.skips ?? {}, m);
    const amount = r.amounts?.[m] ?? r.amount;
    schedule.push({
      month: m,
      amount: skipped ? 0 : amount,
      status: r.removed?.includes(m) ? "removed" : skipped ? "skipped" : filedMonths.has(m) || m <= now ? "filed" : "upcoming",
      skip_reason: skipped ? r.skips[m] : undefined,
    });
  }
  return {
    id: r.id,
    property_id: r.property_id,
    category: r.category,
    amount: r.amount,
    day: r.day,
    payment_mode: r.payment_mode,
    note: r.note ?? "",
    start_month: r.start_month,
    end_month: r.end_month ?? null,
    status: r.status,
    schedule,
    nothing_will_file: r.status === "active" && schedule.filter((s) => s.month > now).every((s) => s.status === "skipped"),
  };
}

function applyFilters(list, q) {
  const text = String(q.q ?? "").trim().toLowerCase();
  const min = q.min !== undefined && q.min !== "" ? Number(q.min) : null;
  const max = q.max !== undefined && q.max !== "" ? Number(q.max) : null;
  return list.filter((e) => {
    if (q.property_id && e.property_id !== Number(q.property_id)) return false;
    if (q.category && q.category !== "all" && !e.lines.some((l) => l.category === q.category)) return false;
    if (q.payment_mode && q.payment_mode !== "all" && e.payment_mode !== q.payment_mode) return false;
    if (q.from && e.date < q.from) return false;
    if (q.to && e.date > q.to) return false;
    // Amount range matches the entry total, not individual lines.
    if (min !== null && e.total < min) return false;
    if (max !== null && e.total > max) return false;
    if (q.attachments === "with" && !(e.attachments ?? []).length) return false;
    if (q.attachments === "without" && (e.attachments ?? []).length) return false;
    if (q.recurring === "true" && !e.lines.some((l) => l.rule_id)) return false;
    if (text) {
      const hay = [...e.lines.flatMap((l) => [l.category, l.note, String(l.amount)]), MODE_LABELS[e.payment_mode], e.payment_mode, e.notes, String(e.total)]
        .join(" ")
        .toLowerCase();
      if (!hay.includes(text)) return false;
    }
    return true;
  });
}

const SORTS = {
  date_desc: (a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : b.id - a.id),
  date_asc: (a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : a.id - b.id),
  amount_desc: (a, b) => b.total - a.total,
  amount_asc: (a, b) => a.total - b.total,
};

const csvCell = (v) => {
  const s = String(v ?? "");
  // Neutralise spreadsheet formulas and quote.
  const safe = /^[=+\-@]/.test(s) ? `'${s}` : s;
  return /[",\n]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
};

export function expensesRouter(db) {
  const router = Router();

  async function scopedEntry(req) {
    const e = await db.findDoc("expenses", { id: Number(req.params.id) });
    if (!e || e.org_id !== req.scope.org_id) throw new InputError("Expense not found", 404);
    return e;
  }

  async function scopedRule(req) {
    const r = await db.findDoc("expense_rules", { id: Number(req.params.id) });
    if (!r || r.org_id !== req.scope.org_id) throw new InputError("Repeating expense not found", 404);
    return r;
  }

  router.get("/meta", handle(async (_req, res) => res.json({ categories: EXPENSE_CATEGORIES, payment_modes: MODE_LABELS, export_max: EXPORT_MAX })));

  router.get(
    "/",
    handle(async (req, res) => {
      await fileRecurring(db, req.scope.org_id);
      const all = await db.findDocs("expenses", { org_id: req.scope.org_id });
      const list = applyFilters(all, req.query).sort(SORTS[req.query.sort] ?? SORTS.date_desc);
      const page = Math.max(1, Number(req.query.page) || 1);
      const size = Math.min(100, Math.max(1, Number(req.query.page_size) || 25));
      const cache = new Map();
      const items = [];
      for (const e of list.slice((page - 1) * size, page * size)) items.push(await publicEntry(db, e, cache));
      return res.json({
        items,
        total: list.length,
        sum: round2(list.reduce((s, e) => s + e.total, 0)),
        page,
        page_size: size,
        has_any: all.length > 0,
      });
    }),
  );

  router.get(
    "/export",
    handle(async (req, res) => {
      await fileRecurring(db, req.scope.org_id);
      const list = applyFilters(await db.findDocs("expenses", { org_id: req.scope.org_id }), req.query).sort(SORTS[req.query.sort] ?? SORTS.date_desc);
      if (!list.length) throw new InputError("There is nothing to export for these filters");
      if (list.length > EXPORT_MAX)
        throw new InputError(`${list.length} entries — more than the ${EXPORT_MAX} an export can hold. Narrow the period and try again.`);
      const cache = new Map();
      const rows = [["Entry", "Date", "Property", "Category", "Amount", "Line note", "Payment mode", "Repeats monthly", "Skipped", "Entry total", "Notes", "Added by", "Added on"]];
      for (const e of list) {
        const p = await publicEntry(db, e, cache);
        for (const l of e.lines) {
          rows.push([e.id, e.date, p.property.title, l.category, l.skipped ? 0 : l.amount, l.note, p.payment_mode_label, l.rule_id ? "Yes" : "No", l.skipped ? "Yes" : "No", e.total, e.notes, p.added_by, e.created_at.slice(0, 10)]);
        }
      }
      res.setHeader("Content-Type", "text/csv; charset=utf-8");
      res.setHeader("Content-Disposition", `attachment; filename="expenses-${todayStr()}.csv"`);
      return res.send(rows.map((r) => r.map(csvCell).join(",")).join("\n"));
    }),
  );

  // Attachment (bill / receipt photo) → { url } to put on an entry.
  router.post(
    "/attachments",
    handle(async (req, res) => {
      const result = await savePhoto(`expenses/${req.scope.org_id}`, req.body);
      if (result.error) throw new InputError(result.error);
      return res.status(201).json({ url: result.url, name: String(req.body?.name ?? "").slice(0, 120) });
    }),
  );

  function validAttachments(list) {
    if (list === undefined) return undefined;
    if (!Array.isArray(list) || list.length > 10) throw new InputError("Up to 10 attachments per entry");
    return list.map((a) => {
      const url = String(a?.url ?? a ?? "");
      if (!url.startsWith("/media/expenses/")) throw new InputError("Upload attachments first");
      return { url, name: String(a?.name ?? "").slice(0, 120) };
    });
  }

  function validEntry(body) {
    const date = String(body?.date ?? "");
    if (!DATE_RE.test(date)) throw new InputError("Pick the expense date");
    if (date > todayStr()) throw new InputError("The expense date can't be in the future");
    const mode = body?.payment_mode ?? "cash";
    if (!EXPENSE_MODES.includes(mode)) throw new InputError("Choose a payment mode");
    if (!Array.isArray(body?.lines) || body.lines.length === 0) throw new InputError("Add at least one expense line");
    if (body.lines.length > 30) throw new InputError("Up to 30 lines per entry");
    return { date, payment_mode: mode, notes: String(body?.notes ?? "").trim().slice(0, 500) };
  }

  router.post(
    "/",
    handle(async (req, res) => {
      const base = validEntry(req.body);
      const property = await orgProperty(db, req.scope.org_id, req.body?.property_id);
      const t = nowIso();
      const lines = [];
      for (const [i, raw] of req.body.lines.entries()) {
        const line = validLine(raw, i);
        if (raw?.repeat_monthly === true) {
          if (line.amount <= 0) throw new InputError(`Line ${i + 1}: a repeating expense needs an amount`);
          const rule = await db.insertDoc("expense_rules", {
            org_id: req.scope.org_id,
            property_id: property.id,
            category: line.category,
            amount: line.amount,
            note: line.note,
            day: Number(base.date.slice(8, 10)),
            payment_mode: base.payment_mode,
            start_month: monthOf(base.date),
            end_month: null,
            skips: {},
            amounts: { [monthOf(base.date)]: line.amount },
            status: "active",
            created_by: req.user.id,
            created_at: t,
            updated_at: t,
          });
          line.rule_id = rule.id;
        }
        lines.push(line);
      }
      const saved = await db.insertDoc("expenses", {
        org_id: req.scope.org_id,
        property_id: property.id,
        ...base,
        attachments: validAttachments(req.body.attachments) ?? [],
        lines,
        total: totalOf(lines),
        created_by: req.user.id,
        created_by_name: byName(req),
        created_at: t,
        updated_at: t,
      });
      // A repeat that starts in an earlier month files the months since.
      await fileRecurring(db, req.scope.org_id);
      return res.status(201).json(await publicEntry(db, saved));
    }),
  );

  router.get("/rules", handle(async (req, res) => {
    const rules = await db.findDocs("expense_rules", { org_id: req.scope.org_id });
    return res.json(rules.sort((a, b) => b.id - a.id).map((r) => publicRule(r)));
  }));

  router.get("/:id", handle(async (req, res) => res.json(await publicEntry(db, await scopedEntry(req)))));

  router.patch(
    "/:id",
    handle(async (req, res) => {
      const e = await scopedEntry(req);
      const base = validEntry({ ...e, ...req.body, lines: req.body?.lines ?? e.lines });
      const set = { ...base, updated_at: nowIso() };
      if (req.body?.property_id !== undefined) set.property_id = (await orgProperty(db, req.scope.org_id, req.body.property_id)).id;
      const att = validAttachments(req.body?.attachments);
      if (att) set.attachments = att;
      if (req.body?.lines) {
        // Lines are matched by `index`; repeating lines keep their rule and can't be removed here.
        const kept = new Set();
        const lines = [];
        for (const [i, raw] of req.body.lines.entries()) {
          const old = Number.isInteger(raw?.index) ? e.lines[raw.index] : undefined;
          const line = validLine(raw, i);
          if (old?.rule_id) {
            kept.add(raw.index);
            Object.assign(line, { rule_id: old.rule_id, category: old.category, skipped: old.skipped, skip_reason: old.skip_reason });
            // A month's own amount; the rule's future amount is edited on the rule.
            const rule = await db.findDoc("expense_rules", { id: old.rule_id });
            if (rule) await db.updateDoc("expense_rules", { id: rule.id }, { amounts: { ...(rule.amounts ?? {}), [monthOf(e.date)]: line.amount } });
          }
          lines.push(line);
        }
        for (const [i, l] of e.lines.entries()) {
          if (l.rule_id && !kept.has(i)) throw new InputError("A repeating line can't be deleted from one month alone. Skip the month instead.");
        }
        set.lines = lines;
        set.total = totalOf(lines);
      }
      const updated = await db.updateDoc("expenses", { id: e.id }, set);
      return res.json(await publicEntry(db, updated));
    }),
  );

  router.delete(
    "/:id",
    handle(async (req, res) => {
      const e = await scopedEntry(req);
      // Deleting a filed month of a repeat removes only this month; the repeat continues.
      for (const l of e.lines) {
        if (!l.rule_id) continue;
        const rule = await db.findDoc("expense_rules", { id: l.rule_id });
        if (rule) await db.updateDoc("expense_rules", { id: rule.id }, { removed: [...new Set([...(rule.removed ?? []), monthOf(e.date)])] });
      }
      await db.deleteDocs("expenses", { id: e.id });
      return res.json({ deleted: true });
    }),
  );

  // ---- Monthly rules ----

  async function filedMonths(rule) {
    const entries = await db.findDocs("expenses", { org_id: rule.org_id });
    return new Set(entries.filter((e) => e.lines.some((l) => l.rule_id === rule.id)).map((e) => monthOf(e.date)));
  }

  router.get("/rules/:id", handle(async (req, res) => {
    const r = await scopedRule(req);
    return res.json(publicRule(r, await filedMonths(r)));
  }));

  // Edit: new amount / mode / day apply to the months ahead only.
  router.patch(
    "/rules/:id",
    handle(async (req, res) => {
      const r = await scopedRule(req);
      if (r.status !== "active") throw new InputError("This repeat has ended. Its filed months stay in your ledger.");
      const set = { updated_at: nowIso() };
      if (req.body?.amount !== undefined) {
        const a = Number(req.body.amount);
        if (!Number.isFinite(a) || a <= 0) throw new InputError("Enter the amount for the months ahead");
        set.amount = round2(a);
        // Pin past/current months to what they were so only future months change.
        const filed = await filedMonths(r);
        const amounts = { ...(r.amounts ?? {}) };
        for (const m of filed) amounts[m] ??= r.amount;
        set.amounts = amounts;
      }
      if (req.body?.payment_mode !== undefined) {
        if (!EXPENSE_MODES.includes(req.body.payment_mode)) throw new InputError("Choose a payment mode");
        set.payment_mode = req.body.payment_mode;
      }
      if (req.body?.day !== undefined) {
        const d = Number(req.body.day);
        if (!Number.isInteger(d) || d < 1 || d > 31) throw new InputError("Day must be 1–31");
        set.day = d;
      }
      if (req.body?.note !== undefined) set.note = String(req.body.note).slice(0, 200);
      const updated = await db.updateDoc("expense_rules", { id: r.id }, set);
      return res.json({ ...publicRule(updated, await filedMonths(updated)), message: "Repeat updated. Months already filed are unchanged." });
    }),
  );

  async function setSkip(req, skip) {
    const r = await scopedRule(req);
    const month = String(req.body?.month ?? "");
    if (!MONTH_RE.test(month) || month < r.start_month) throw new InputError("Pick a month of this repeat");
    if (r.end_month && month > r.end_month) throw new InputError("This repeat has ended. Its filed months stay in your ledger.");
    const skips = { ...(r.skips ?? {}) };
    if (skip) skips[month] = String(req.body?.reason ?? "").trim().slice(0, 200);
    else delete skips[month];
    const updated = await db.updateDoc("expense_rules", { id: r.id }, { skips, updated_at: nowIso() });
    // Already filed? Update that month's line in place (₹0 when skipped).
    const entries = await db.findDocs("expenses", { org_id: r.org_id });
    for (const e of entries) {
      if (monthOf(e.date) !== month) continue;
      const idx = e.lines.findIndex((l) => l.rule_id === r.id);
      if (idx === -1) continue;
      const lines = e.lines.map((l, i) => (i === idx ? { ...l, skipped: skip, skip_reason: skip ? skips[month] : undefined } : l));
      await db.updateDoc("expenses", { id: e.id }, { lines, total: totalOf(lines), updated_at: nowIso() });
    }
    const pub = publicRule(updated, await filedMonths(updated));
    return {
      ...pub,
      message: pub.nothing_will_file ? "Nothing will file. Unskip a month from Edit, or delete the repeat." : skip ? `${month} skipped` : `${month} will file again`,
    };
  }

  router.post("/rules/:id/skip", handle(async (req, res) => res.json(await setSkip(req, true))));
  router.post("/rules/:id/unskip", handle(async (req, res) => res.json(await setSkip(req, false))));

  // Stop from today: filed months stay; upcoming months are no longer filed.
  router.post(
    "/rules/:id/stop",
    handle(async (req, res) => {
      const r = await scopedRule(req);
      if (r.status !== "active") throw new InputError("This repeat has already ended");
      const now = monthOf(todayStr());
      const updated = await db.updateDoc("expense_rules", { id: r.id }, { status: "stopped", end_month: now < r.start_month ? r.start_month : now, updated_at: nowIso() });
      return res.json({ ...publicRule(updated, await filedMonths(updated)), message: "This repeat has ended. Its filed months stay in your ledger." });
    }),
  );

  return router;
}
