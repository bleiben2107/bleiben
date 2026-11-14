import { Router } from "express";

import { DATE_RE, InputError, OFFLINE_SOURCES, SOURCES, addDays, nights, orgRooms, todayStr } from "../bookings/core.js";
import { fileRecurring } from "./expenses.js";

/**
 * Host dashboard figures (REA 08 §1, validated against the tutorial):
 * Net revenue, Expenses, NOI, Occupancy, Net ADR, Net RevPAR — each against
 * the previous period of the same length — plus Today, sources, where money
 * goes, a properties ranking, monthly revenue/expenses and a 13-week outlook.
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

const SOURCE_LABELS = SOURCES;

const nightCount = (from, to) => nights(from, to).length;

/** Typical OTA commission, used for "saved in commission" on direct bookings. */
const OTA_COMMISSION = 0.15;

// Revenue counts these in full; cancelled / no-show keep only what was retained.
const EARNING = ["pending_payment", "confirmed", "checked_in", "checked_out"];
const RETAINED = ["cancelled", "no_show"];
const OCCUPYING = ["pending_payment", "confirmed", "checked_in", "checked_out"];

const round = (n, d = 0) => {
  const f = 10 ** d;
  return Math.round((n + Number.EPSILON) * f) / f;
};
const paidOf = (b) => (b.payments ?? []).reduce((s, p) => s + (p.kind === "refund" ? -p.amount : p.amount), 0);
const revenueOf = (b) => (EARNING.includes(b.status) ? b.total : RETAINED.includes(b.status) ? Math.max(0, paidOf(b)) : 0);
const extrasOf = (b) => (EARNING.includes(b.status) ? Number(b.quote?.extra_guest_charge ?? 0) : 0);
const pct = (cur, prev) => (prev ? round(((cur - prev) / Math.abs(prev)) * 100, 1) : cur ? null : 0);

/** Nights of [checkIn, checkOut) that fall inside [from, to] (inclusive dates). */
function overlap(checkIn, checkOut, from, to) {
  const start = checkIn > from ? checkIn : from;
  const endExcl = checkOut < addDays(to, 1) ? checkOut : addDays(to, 1);
  return start < endExcl ? nightCount(start, endExcl) : 0;
}

export function resolvePeriod(q, today = todayStr()) {
  const period = String(q.period ?? "last_30");
  let from;
  let to;
  const m = /^(last|next)_(\d+)$/.exec(period);
  if (m) {
    const n = Math.min(366, Math.max(1, Number(m[2])));
    if (m[1] === "last") {
      to = today;
      from = addDays(today, -(n - 1));
    } else {
      from = today;
      to = addDays(today, n - 1);
    }
  } else if (period === "custom") {
    from = String(q.from ?? "");
    to = String(q.to ?? "");
    if (!DATE_RE.test(from) || !DATE_RE.test(to) || to < from) throw new InputError("Pick a start and end date");
    if (nightCount(from, addDays(to, 1)) > 731) throw new InputError("Pick a range of two years or less");
  } else {
    throw new InputError("Unknown period");
  }
  const len = nightCount(from, addDays(to, 1));
  return { period, from, to, days: len, compare: { from: addDays(from, -len), to: addDays(from, -1) } };
}

export function dashboardRouter(db) {
  const router = Router();

  router.get(
    "/",
    handle(async (req, res) => {
      const orgId = req.scope.org_id;
      const today = todayStr();
      const range = resolvePeriod(req.query, today);
      const countBy = ["check_in", "check_out", "booked"].includes(req.query.count_by) ? req.query.count_by : "check_in";
      const propertyId = req.query.property_id ? Number(req.query.property_id) : null;
      const city = String(req.query.city ?? "").trim().toLowerCase();

      // Scope: rooms of matching properties.
      let rooms = await orgRooms(db, orgId, propertyId);
      if (city) rooms = rooms.filter((r) => String(r.property.address?.city ?? "").toLowerCase() === city);
      const propIds = new Set(rooms.map((r) => r.property.id));
      const allProps = (await db.findDocs("properties", { org_id: orgId })).filter((p) => p.status !== "deleted");
      const cities = [...new Set(allProps.map((p) => p.address?.city).filter(Boolean))].sort();

      const bookings = (await db.findDocs("bookings", { org_id: orgId })).filter((b) => propIds.has(b.property_id));
      await fileRecurring(db, orgId);
      const expenses = (await db.findDocs("expenses", { org_id: orgId })).filter((e) => propIds.has(e.property_id));

      const keyDate = (b) => (countBy === "booked" ? b.created_at.slice(0, 10) : countBy === "check_out" ? b.check_out : b.check_in);
      const inRange = (d, r) => d >= r.from && d <= r.to;
      const unitsTotal = rooms.reduce((s, r) => s + (r.room.unitCount ?? 1), 0);

      function figures(r, filterProp = null) {
        const bs = bookings.filter((b) => (filterProp == null || b.property_id === filterProp) && inRange(keyDate(b), r));
        const revenue = bs.reduce((s, b) => s + revenueOf(b), 0);
        const extras = bs.reduce((s, b) => s + extrasOf(b), 0);
        const exp = expenses
          .filter((e) => (filterProp == null || e.property_id === filterProp) && inRange(e.date, r))
          .reduce((s, e) => s + e.total, 0);
        const units =
          filterProp == null ? unitsTotal : rooms.filter((x) => x.property.id === filterProp).reduce((s, x) => s + (x.room.unitCount ?? 1), 0);
        const available = units * nightCount(r.from, addDays(r.to, 1));
        // Occupancy uses nights actually stayed inside the range (blocked nights still count as available).
        const booked = bookings
          .filter((b) => (filterProp == null || b.property_id === filterProp) && OCCUPYING.includes(b.status))
          .reduce((s, b) => s + overlap(b.check_in, b.check_out, r.from, r.to), 0);
        const soldNights = bs.filter((b) => EARNING.includes(b.status)).reduce((s, b) => s + nightCount(b.check_in, b.check_out), 0);
        return {
          bookings: bs.filter((b) => EARNING.includes(b.status)).length,
          revenue,
          extras,
          expenses: exp,
          noi: revenue - exp,
          booked_nights: booked,
          available_nights: available,
          occupancy: available ? (booked / available) * 100 : 0,
          adr: soldNights ? revenue / soldNights : 0,
          revpar: available ? revenue / available : 0,
        };
      }

      const cur = figures(range);
      const prev = figures(range.compare);
      const kpis = {
        revenue: { value: round(cur.revenue), stay: round(cur.revenue - cur.extras), extras: round(cur.extras), change: pct(cur.revenue, prev.revenue) },
        expenses: { value: round(cur.expenses), pct_of_revenue: cur.revenue ? round((cur.expenses / cur.revenue) * 100, 1) : null, change: pct(cur.expenses, prev.expenses) },
        noi: { value: round(cur.noi), margin: cur.revenue ? round((cur.noi / cur.revenue) * 100, 1) : null, change: pct(cur.noi, prev.noi) },
        occupancy: {
          value: round(cur.occupancy, 1),
          booked_nights: cur.booked_nights,
          available_nights: cur.available_nights,
          change_pts: round(cur.occupancy - prev.occupancy, 1),
        },
        adr: { value: round(cur.adr), change: pct(cur.adr, prev.adr) },
        revpar: { value: round(cur.revpar), change: pct(cur.revpar, prev.revpar) },
        bookings: { value: cur.bookings, change: pct(cur.bookings, prev.bookings) },
      };

      // Today column.
      const live = bookings.filter((b) => OCCUPYING.includes(b.status) || b.status === "held");
      const brief = (b) => ({ id: b.id, code: b.code, guest_name: b.guest?.name ?? "", check_in: b.check_in, check_out: b.check_out, source: b.source, source_label: SOURCE_LABELS[b.source] ?? b.source, status: b.status });
      const todayLists = {
        check_ins: live.filter((b) => b.check_in === today && b.status !== "checked_out"),
        check_outs: live.filter((b) => b.check_out === today),
        ongoing: live.filter((b) => b.status === "checked_in" || (b.check_in < today && b.check_out > today && b.status !== "checked_out")),
        arriving_soon: live.filter((b) => b.check_in > today && b.check_in <= addDays(today, 2)),
      };
      const todayOut = Object.fromEntries(Object.entries(todayLists).map(([k, list]) => [k, { count: list.length, items: list.slice(0, 5).map(brief) }]));

      // Where bookings come from (blocked nights aren't a source).
      const srcMap = new Map();
      for (const b of bookings.filter((x) => EARNING.includes(x.status) && inRange(keyDate(x), range))) {
        const s = srcMap.get(b.source) ?? { source: b.source, label: SOURCE_LABELS[b.source] ?? b.source, bookings: 0, nights: 0, revenue: 0 };
        s.bookings += 1;
        s.nights += nightCount(b.check_in, b.check_out);
        s.revenue += b.total;
        srcMap.set(b.source, s);
      }
      const srcTotalN = [...srcMap.values()].reduce((s, x) => s + x.nights, 0);
      const srcTotalR = [...srcMap.values()].reduce((s, x) => s + x.revenue, 0);
      const sources = [...srcMap.values()]
        .map((s) => ({
          ...s,
          revenue: round(s.revenue),
          share_nights: srcTotalN ? round((s.nights / srcTotalN) * 100, 1) : 0,
          share_revenue: srcTotalR ? round((s.revenue / srcTotalR) * 100, 1) : 0,
          adr: s.nights ? round(s.revenue / s.nights) : 0,
          offline: OFFLINE_SOURCES.includes(s.source),
          saved_commission: s.source === "direct" || OFFLINE_SOURCES.includes(s.source) ? round(s.revenue * OTA_COMMISSION) : 0,
        }))
        .sort((a, b) => b.revenue - a.revenue);

      // Where money goes (by expense date).
      const catMap = new Map();
      for (const e of expenses.filter((x) => inRange(x.date, range))) {
        for (const l of e.lines) if (!l.skipped) catMap.set(l.category, (catMap.get(l.category) ?? 0) + l.amount);
      }
      const catTotal = [...catMap.values()].reduce((s, v) => s + v, 0);
      const money = [...catMap.entries()]
        .map(([category, amount]) => ({ category, amount: round(amount), share: catTotal ? round((amount / catTotal) * 100, 1) : 0 }))
        .sort((a, b) => b.amount - a.amount);

      // Properties ranking.
      const properties = [...propIds].map((id) => {
        const p = rooms.find((r) => r.property.id === id).property;
        const f = figures(range, id);
        return {
          id,
          title: p.title || "Untitled property",
          city: p.address?.city ?? "",
          revenue: round(f.revenue),
          occupancy: round(f.occupancy, 1),
          adr: round(f.adr),
          expenses: round(f.expenses),
          expense_pct: f.revenue ? round((f.expenses / f.revenue) * 100, 1) : null,
          bookings: f.bookings,
        };
      });

      // Revenue and expenses by month for the chosen year.
      const year = Number(req.query.year) || Number(today.slice(0, 4));
      const monthly = [];
      for (let m = 1; m <= 12; m++) {
        const mm = String(m).padStart(2, "0");
        const from = `${year}-${mm}-01`;
        const to = addDays(m === 12 ? `${year + 1}-01-01` : `${year}-${String(m + 1).padStart(2, "0")}-01`, -1);
        const f = figures({ from, to });
        monthly.push({ month: `${year}-${mm}`, revenue: round(f.revenue), expenses: round(f.expenses), noi: round(f.noi), margin: f.revenue ? round((f.noi / f.revenue) * 100, 1) : null });
      }
      const years = [...new Set([Number(today.slice(0, 4)), ...bookings.map((b) => Number(b.check_in.slice(0, 4))), ...expenses.map((e) => Number(e.date.slice(0, 4)))])].sort((a, b) => b - a);

      // 13-week occupancy outlook from today. Blocked nights count as "not offered" only when every unit is blocked.
      const blocks = await db.findDocs("blocks", { org_id: orgId });
      const blockedSet = new Set(blocks.filter((x) => rooms.some((r) => r.room.id === x.room_id)).map((x) => `${x.room_id}:${x.date}`));
      const outlook = [];
      for (let w = 0; w < 13; w++) {
        const from = addDays(today, w * 7);
        const to = addDays(from, 6);
        let offered = 0;
        for (let d = from; d <= to; d = addDays(d, 1)) {
          for (const r of rooms) if (!blockedSet.has(`${r.room.id}:${d}`)) offered += r.room.unitCount ?? 1;
        }
        const booked = bookings.filter((b) => OCCUPYING.includes(b.status)).reduce((s, b) => s + overlap(b.check_in, b.check_out, from, to), 0);
        const p = offered ? (booked / offered) * 100 : 0;
        outlook.push({
          from,
          to,
          booked_nights: booked,
          offered_nights: offered,
          pct: round(p, 1),
          band: !offered ? "not_offered" : p >= 50 ? "high" : p >= 25 ? "mid" : "low",
        });
      }

      // Alerts.
      const alerts = [];
      const missing = bookings.filter((b) => EARNING.includes(b.status) && !(b.total > 0)).length;
      if (missing) alerts.push({ kind: "missing_revenue", count: missing, text: `${missing} booking${missing === 1 ? "" : "s"} missing revenue data` });
      const dueSoon = bookings.filter((b) => ["pending_payment", "confirmed"].includes(b.status) && b.check_in <= addDays(today, 2) && b.check_in >= today && paidOf(b) < b.total).length;
      if (dueSoon) alerts.push({ kind: "balance_due", count: dueSoon, text: `${dueSoon} arriving guest${dueSoon === 1 ? " has" : "s have"} a balance to collect` });
      const holds = bookings.filter((b) => b.status === "held").length;
      if (holds) alerts.push({ kind: "holds", count: holds, text: `${holds} date hold${holds === 1 ? "" : "s"} waiting for payment` });

      return res.json({
        today,
        range: { ...range, count_by: countBy },
        filters: { cities, properties: allProps.map((p) => ({ id: p.id, title: p.title || "Untitled property", city: p.address?.city ?? "" })) },
        totals: { properties: propIds.size, units: unitsTotal },
        kpis,
        today_panel: todayOut,
        sources,
        money,
        properties,
        monthly: { year, years, months: monthly },
        outlook,
        alerts,
      });
    }),
  );

  return router;
}
