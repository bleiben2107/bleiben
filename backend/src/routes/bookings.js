import { Router } from "express";

import {
  InputError,
  OFFLINE_SOURCES,
  PAYMENT_METHODS,
  SOURCES,
  TRANSITIONS,
  addDays,
  assertAvailable,
  bookingCode,
  findRoom,
  nowIso,
  occupies,
  quote,
  requireRange,
  todayStr,
  toDate,
  withLocks,
} from "../bookings/core.js";
import { can } from "../roles.js";

const HOLD_MINUTES = 15;
const PHONE_RE = /^\+?[0-9 ()-]{7,20}$/;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$/;

const handle = (fn) => async (req, res, next) => {
  try {
    if (req.scope?.org_id == null) throw new InputError("Choose an organisation (X-Org-Id) first");
    return await fn(req, res);
  } catch (err) {
    if (err instanceof InputError) return res.status(err.status).json({ detail: err.message, ...err.extra });
    return next(err);
  }
};

const paid = (b) => (b.payments ?? []).filter((p) => p.kind !== "refund").reduce((s, p) => s + p.amount, 0)
  - (b.payments ?? []).filter((p) => p.kind === "refund").reduce((s, p) => s + p.amount, 0);

function paymentStatus(b) {
  const p = paid(b);
  if (b.total > 0 && p >= b.total) return "paid";
  if (p > 0) return "partial";
  return "pending";
}

/** API shape (homyhuts columns: Booking ID · Trip status · Check in/out · Guest · Guests · Source · Payment · Amount). */
export async function publicBooking(db, b, cache = {}) {
  const room = cache.rooms?.get(b.room_id) ?? (await db.findDoc("rooms", { id: b.room_id }));
  const property = cache.props?.get(b.property_id) ?? (await db.findDoc("properties", { id: b.property_id }));
  const p = paid(b);
  const today = todayStr();
  let tripStatus = "upcoming";
  if (["cancelled", "expired", "no_show"].includes(b.status)) tripStatus = "cancelled";
  else if (b.status === "checked_out" || b.check_out < today) tripStatus = "completed";
  else if (b.status === "checked_in" || (b.check_in <= today && b.check_out > today)) tripStatus = "ongoing";
  return {
    id: b.id,
    code: b.code,
    status: b.status,
    trip_status: tripStatus,
    source: b.source,
    source_label: SOURCES[b.source] ?? b.source,
    property: property ? { id: property.id, title: property.title || "Untitled property", city: property.address?.city ?? "" } : null,
    room: room ? { id: room.id, name: room.name } : null,
    check_in: b.check_in,
    check_out: b.check_out,
    nights: Math.round((toDate(b.check_out) - toDate(b.check_in)) / 86400000),
    guest: b.guest,
    adults: b.adults,
    children: b.children ?? 0,
    guests: (b.adults ?? 1) + (b.children ?? 0),
    total: b.total,
    paid: p,
    balance: Math.max(0, b.total - p),
    payment_status: paymentStatus(b),
    payments: b.payments ?? [],
    quote: b.quote ?? null,
    notes: b.notes ?? "",
    hold_expires_at: b.status === "held" ? b.hold_expires_at : null,
    cancel_reason: b.cancel_reason ?? null,
    events: b.events ?? [],
    booked_at: b.created_at,
    updated_at: b.updated_at,
  };
}

function validateGuest(body) {
  const g = body?.guest ?? {};
  const name = String(g.name ?? "").trim();
  if (name.length < 2) throw new InputError("Enter the guest's name");
  const phone = String(g.phone ?? "").trim();
  if (phone && !PHONE_RE.test(phone)) throw new InputError("Enter a valid guest phone number");
  const email = String(g.email ?? "").trim().toLowerCase();
  if (email && !EMAIL_RE.test(email)) throw new InputError("Enter a valid guest email");
  if (!phone && !email) throw new InputError("Add the guest's phone or email");
  return { name: name.slice(0, 80), phone, email };
}

function validateGuests(body, room) {
  const adults = Number(body?.adults ?? 1);
  const children = Number(body?.children ?? 0);
  if (!Number.isInteger(adults) || adults < 1) throw new InputError("At least one adult");
  if (!Number.isInteger(children) || children < 0) throw new InputError("Children must be 0 or more");
  const max = (room.maxAdults ?? 2) + (room.maxChildren ?? 0);
  if (adults + children > max + 4) throw new InputError(`${room.name} takes up to ${max} guests`);
  return { adults, children };
}

function validatePayment(body, { required = false } = {}) {
  const amount = Number(body?.amount ?? 0);
  if (!amount && !required) return null;
  if (!Number.isFinite(amount) || amount <= 0) throw new InputError("Enter a payment amount above 0");
  const method = body?.method ?? "cash";
  if (!PAYMENT_METHODS.includes(method)) throw new InputError(`Payment method must be one of: ${PAYMENT_METHODS.join(", ")}`);
  return { amount: Math.round(amount * 100) / 100, method, reference: String(body?.reference ?? "").slice(0, 80), note: String(body?.note ?? "").slice(0, 200) };
}

const event = (req, action, detail = "") => ({ at: nowIso(), by: req.user.name || req.user.email || `user ${req.user.id}`, action, detail });

/** Marks expired holds; safe to call often (also runs on a timer in index.js). */
export async function expireHolds(db) {
  const now = Date.now();
  let n = 0;
  for (const b of await db.findDocs("bookings", { status: "held" })) {
    if (Date.parse(b.hold_expires_at || 0) <= now) {
      await db.updateDoc("bookings", { id: b.id }, {
        status: "expired",
        updated_at: nowIso(),
        events: [...(b.events ?? []), { at: nowIso(), by: "system", action: "expired", detail: "Hold released" }],
      });
      n += 1;
    }
  }
  return n;
}

// ── List filters / tabs (homyhuts Reservations tabs) ────────────────────────

const TABS = {
  all: () => true,
  upcoming: (b, t) => ["confirmed", "pending_payment", "held"].includes(b.status) && b.check_in > t,
  arriving_soon: (b, t) => ["confirmed", "pending_payment"].includes(b.status) && b.check_in > t && b.check_in <= addDays(t, 2),
  checking_in: (b, t) => ["confirmed", "pending_payment"].includes(b.status) && b.check_in === t,
  checking_out: (b, t) => ["checked_in", "confirmed"].includes(b.status) && b.check_out === t,
  in_house: (b) => b.status === "checked_in",
  pending_payment: (b) => occupies(b) && paymentStatus(b) !== "paid",
  completed: (b) => b.status === "checked_out",
  cancelled: (b) => ["cancelled", "expired", "no_show"].includes(b.status),
  offline: (b) => OFFLINE_SOURCES.includes(b.source),
};

export function bookingsRouter(db) {
  const router = Router();

  async function orgBookings(orgId) {
    return db.findDocs("bookings", { org_id: orgId });
  }

  async function scoped(req, id) {
    const b = await db.findDoc("bookings", { id: Number(id) });
    if (!b || b.org_id !== req.scope.org_id) throw new InputError("Booking not found", 404);
    return b;
  }

  function applyFilters(list, query) {
    const t = todayStr();
    const tab = TABS[query.tab] ?? TABS.all;
    const q = String(query.q ?? "").trim().toLowerCase();
    return list.filter((b) => {
      if (!tab(b, t)) return false;
      if (q && ![b.code, b.guest?.name, b.guest?.phone, b.guest?.email].join(" ").toLowerCase().includes(q)) return false;
      if (query.property_id && b.property_id !== Number(query.property_id)) return false;
      if (query.room_id && b.room_id !== Number(query.room_id)) return false;
      if (query.source && query.source !== "all" && b.source !== query.source) return false;
      if (query.status && query.status !== "all" && b.status !== query.status) return false;
      if (query.payment && query.payment !== "all" && paymentStatus(b) !== query.payment) return false;
      if (query.check_in_from && b.check_in < query.check_in_from) return false;
      if (query.check_in_to && b.check_in > query.check_in_to) return false;
      if (query.booked_from && b.created_at.slice(0, 10) < query.booked_from) return false;
      if (query.booked_to && b.created_at.slice(0, 10) > query.booked_to) return false;
      return true;
    });
  }

  router.get(
    "/",
    handle(async (req, res) => {
      await expireHolds(db);
      const all = await orgBookings(req.scope.org_id);
      const filtered = applyFilters(all, req.query).sort((a, b) =>
        req.query.sort === "booked" ? (a.created_at < b.created_at ? 1 : -1) : a.check_in < b.check_in ? -1 : 1,
      );
      const page = Math.max(1, Number(req.query.page) || 1);
      const size = Math.min(100, Math.max(1, Number(req.query.page_size) || 25));
      const items = [];
      for (const b of filtered.slice((page - 1) * size, page * size)) items.push(await publicBooking(db, b));
      const t = todayStr();
      const counts = Object.fromEntries(Object.entries(TABS).map(([k, f]) => [k, all.filter((b) => f(b, t)).length]));
      return res.json({ items, total: filtered.length, page, page_size: size, counts });
    }),
  );

  // Price + availability preview for the Create Booking form.
  router.post(
    "/quote",
    handle(async (req, res) => {
      const { room_id: roomId, check_in: checkIn, check_out: checkOut } = req.body ?? {};
      requireRange(checkIn, checkOut);
      const found = await findRoom(db, req.scope.org_id, roomId);
      if (!found) throw new InputError("Room not found", 404);
      const guests = (Number(req.body?.adults) || 1) + (Number(req.body?.children) || 0);
      try {
        const snapshot = await assertAvailable(db, found.room, found.property, checkIn, checkOut);
        return res.json({ available: true, ...quote(found.room, found.property, snapshot, guests) });
      } catch (err) {
        if (err instanceof InputError && err.status === 409) return res.json({ available: false, detail: err.message, ...err.extra });
        throw err;
      }
    }),
  );

  // Create (manual / offline / direct). `hold: true` creates a 15-minute hold instead.
  router.post(
    "/",
    handle(async (req, res) => {
      const body = req.body ?? {};
      requireRange(body.check_in, body.check_out);
      const found = await findRoom(db, req.scope.org_id, body.room_id);
      if (!found) throw new InputError("Room not found", 404);
      const { room, property } = found;
      const guest = validateGuest(body);
      const { adults, children } = validateGuests(body, room);
      const source = body.source ?? "manual";
      if (!SOURCES[source]) throw new InputError(`Source must be one of: ${Object.keys(SOURCES).join(", ")}`);
      const payment = validatePayment(body.payment);
      const isHold = body.hold === true;

      const created = await withLocks([`room:${room.id}`], async () => {
        const snapshot = await assertAvailable(db, room, property, body.check_in, body.check_out);
        const q = quote(room, property, snapshot, adults + children);
        let total = q.total;
        if (body.total !== undefined && body.total !== null && body.total !== "") {
          total = Number(body.total);
          if (!Number.isFinite(total) || total < 0) throw new InputError("Enter a valid total amount");
        }
        if (payment && payment.amount > total) throw new InputError("The payment is more than the booking total");
        const now = nowIso();
        const status = isHold ? "held" : payment || total === 0 || body.confirm === true ? "confirmed" : "pending_payment";
        const payments = payment ? [{ ...payment, kind: "payment", at: now, by: req.user.name || req.user.email }] : [];
        return db.insertDoc("bookings", {
          org_id: req.scope.org_id,
          property_id: property.id,
          room_id: room.id,
          code: bookingCode(),
          status,
          source,
          check_in: body.check_in,
          check_out: body.check_out,
          guest,
          adults,
          children,
          quote: q,
          total,
          payments,
          paid: payments.reduce((s, p) => s + p.amount, 0),
          notes: String(body.notes ?? "").slice(0, 1000),
          hold_expires_at: isHold ? new Date(Date.now() + HOLD_MINUTES * 60000).toISOString() : null,
          created_by: req.user.id,
          created_at: now,
          updated_at: now,
          events: [event(req, isHold ? "held" : "created", `${SOURCES[source]} · ${status.replace("_", " ")}`)],
        });
      });
      return res.status(201).json(await publicBooking(db, created));
    }),
  );

  router.get(
    "/export",
    handle(async (req, res) => {
      const list = applyFilters(await orgBookings(req.scope.org_id), req.query);
      const rows = [["Booking ID", "Status", "Source", "Property", "Room", "Check-in", "Check-out", "Nights", "Guest", "Phone", "Email", "Guests", "Total", "Paid", "Balance", "Booked at"]];
      for (const b of list) {
        const p = await publicBooking(db, b);
        rows.push([p.code, p.status, p.source_label, p.property?.title ?? "", p.room?.name ?? "", p.check_in, p.check_out, p.nights,
          p.guest?.name ?? "", p.guest?.phone ?? "", p.guest?.email ?? "", p.guests, p.total, p.paid, p.balance, p.booked_at]);
      }
      const csv = rows.map((r) => r.map((v) => `"${String(v ?? "").replace(/"/g, '""')}"`).join(",")).join("\r\n");
      res.setHeader("Content-Type", "text/csv; charset=utf-8");
      res.setHeader("Content-Disposition", `attachment; filename="reservations-${todayStr()}.csv"`);
      return res.send(csv);
    }),
  );

  router.get(
    "/:id",
    handle(async (req, res) => res.json(await publicBooking(db, await scoped(req, req.params.id)))),
  );

  // Edit permitted details. Changing dates/room re-checks availability.
  router.patch(
    "/:id",
    handle(async (req, res) => {
      const b = await scoped(req, req.params.id);
      if (["cancelled", "expired", "no_show", "checked_out"].includes(b.status)) throw new InputError("This booking can no longer be edited", 409);
      const body = req.body ?? {};
      const set = { updated_at: nowIso() };
      const changes = [];
      if (body.guest) {
        set.guest = validateGuest({ guest: { ...b.guest, ...body.guest } });
        changes.push("guest details");
      }
      if (body.notes !== undefined) {
        set.notes = String(body.notes).slice(0, 1000);
        changes.push("notes");
      }
      const roomId = body.room_id ?? b.room_id;
      const checkIn = body.check_in ?? b.check_in;
      const checkOut = body.check_out ?? b.check_out;
      const movesStay = roomId !== b.room_id || checkIn !== b.check_in || checkOut !== b.check_out;
      const found = await findRoom(db, req.scope.org_id, roomId);
      if (!found) throw new InputError("Room not found", 404);
      if (body.adults !== undefined || body.children !== undefined) {
        Object.assign(set, validateGuests({ adults: body.adults ?? b.adults, children: body.children ?? b.children }, found.room));
        changes.push("guest count");
      }
      if (body.total !== undefined) {
        const total = Number(body.total);
        if (!Number.isFinite(total) || total < 0) throw new InputError("Enter a valid total amount");
        set.total = total;
        changes.push("total");
      }
      const updated = await withLocks([`room:${b.room_id}`, `room:${roomId}`], async () => {
        if (movesStay) {
          if (b.status === "checked_in" && checkIn !== b.check_in) throw new InputError("The guest has checked in; only the check-out date can change", 409);
          requireRange(checkIn, checkOut);
          const snapshot = await assertAvailable(db, found.room, found.property, checkIn, checkOut, b.id);
          Object.assign(set, { room_id: roomId, property_id: found.property.id, check_in: checkIn, check_out: checkOut });
          if (body.total === undefined) {
            set.quote = quote(found.room, found.property, snapshot, (set.adults ?? b.adults) + (set.children ?? b.children ?? 0));
            set.total = set.quote.total;
          }
          changes.push("stay dates/room");
        }
        set.events = [...(b.events ?? []), event(req, "edited", changes.join(", ") || "no changes")];
        return db.updateDoc("bookings", { id: b.id }, set);
      });
      return res.json(await publicBooking(db, updated));
    }),
  );

  async function transition(req, res, to, extra = {}, detail = "") {
    const b = await scoped(req, req.params.id);
    if (!(TRANSITIONS[b.status] ?? []).includes(to)) {
      throw new InputError(`A ${b.status.replace("_", " ")} booking can't be marked ${to.replace("_", " ")}`, 409);
    }
    const updated = await db.updateDoc("bookings", { id: b.id }, {
      status: to,
      ...extra,
      updated_at: nowIso(),
      events: [...(b.events ?? []), event(req, to, detail)],
    });
    return res.json(await publicBooking(db, updated));
  }

  router.post("/:id/confirm", handle(async (req, res) => {
    const b = await scoped(req, req.params.id);
    if (b.status === "held" && Date.parse(b.hold_expires_at) <= Date.now()) throw new InputError("This hold has expired", 409);
    return transition(req, res, "confirmed", { hold_expires_at: null });
  }));
  router.post("/:id/check-in", handle((req, res) => transition(req, res, "checked_in", { checked_in_at: nowIso() })));
  router.post("/:id/check-out", handle((req, res) => transition(req, res, "checked_out", { checked_out_at: nowIso() })));
  router.post("/:id/no-show", handle((req, res) => transition(req, res, "no_show")));
  router.post("/:id/cancel", handle(async (req, res) => {
    if (req.membership && !can(req.membership.role, "bookings.cancel")) {
      return res.status(403).json({ detail: "Your role cannot cancel bookings" });
    }
    const reason = String(req.body?.reason ?? "").trim();
    if (reason.length < 3) throw new InputError("Add a short reason for cancelling");
    return transition(req, res, "cancelled", { cancel_reason: reason.slice(0, 300), cancelled_at: nowIso() }, reason.slice(0, 120));
  }));

  // Record a payment (advance / balance) or a refund.
  router.post(
    "/:id/payments",
    handle(async (req, res) => {
      const b = await scoped(req, req.params.id);
      const payment = validatePayment(req.body, { required: true });
      const kind = req.body?.kind === "refund" ? "refund" : "payment";
      const currentPaid = paid(b);
      if (kind === "payment" && currentPaid + payment.amount > b.total) throw new InputError(`Only ₹${b.total - currentPaid} is left to pay`);
      if (kind === "refund" && payment.amount > currentPaid) throw new InputError("You can't refund more than was paid");
      const payments = [...(b.payments ?? []), { ...payment, kind, at: nowIso(), by: req.user.name || req.user.email }];
      const set = { payments, paid: currentPaid + (kind === "refund" ? -payment.amount : payment.amount), updated_at: nowIso() };
      if (b.status === "pending_payment" && kind === "payment") set.status = "confirmed";
      set.events = [...(b.events ?? []), event(req, kind === "refund" ? "refunded" : "payment", `₹${payment.amount} · ${payment.method}`)];
      const updated = await db.updateDoc("bookings", { id: b.id }, set);
      return res.status(201).json(await publicBooking(db, updated));
    }),
  );

  return router;
}
