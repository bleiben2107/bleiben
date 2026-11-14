/**
 * Inventory core shared by Calendar, Reservations and the Dashboard
 * (MVP plan §2 / §4). Dates are "YYYY-MM-DD"; a stay covers the nights
 * [check_in, check_out) — check-out day is free for the next guest.
 *
 * Storage (generic docs, org-scoped):
 *   rooms      — room types with unitCount (from routes/properties.js)
 *   blocks     — one doc per room per blocked night {room_id, date, reason, notes}
 *   rates      — one doc per room per priced night  {room_id, date, price}
 *   bookings   — reservations (see BOOKING_STATUSES)
 */
import crypto from "node:crypto";

export const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const DAY = 86400000;

export class InputError extends Error {
  constructor(message, status = 400, extra = {}) {
    super(message);
    this.status = status;
    this.extra = extra;
  }
}

export const nowIso = () => new Date().toISOString();

export function toDate(s) {
  if (!DATE_RE.test(String(s || ""))) return null;
  const d = new Date(`${s}T00:00:00Z`);
  return Number.isNaN(d.getTime()) ? null : d;
}

export const fmt = (d) => d.toISOString().slice(0, 10);
export const addDays = (s, n) => fmt(new Date(toDate(s).getTime() + n * DAY));
export const todayStr = () => fmt(new Date(Date.now() + 5.5 * 3600000)); // IST calendar day

/** Every date from `from` up to but excluding `to`. */
export function nights(from, to) {
  const out = [];
  for (let d = toDate(from); d < toDate(to); d = new Date(d.getTime() + DAY)) out.push(fmt(d));
  return out;
}

export function requireRange(from, to, { maxNights = 366, label = "dates" } = {}) {
  const a = toDate(from);
  const b = toDate(to);
  if (!a || !b) throw new InputError(`Enter valid ${label} (YYYY-MM-DD)`);
  if (b <= a) throw new InputError("Check-out must be after check-in");
  if ((b - a) / DAY > maxNights) throw new InputError(`That range is too long (max ${maxNights} nights)`);
}

// ── Statuses ────────────────────────────────────────────────────────────────

export const BOOKING_STATUSES = [
  "inquiry",
  "held",
  "pending_payment",
  "confirmed",
  "checked_in",
  "checked_out",
  "cancelled",
  "expired",
  "no_show",
];

/** Statuses that occupy inventory. A hold only counts until it expires. */
export function occupies(b, now = Date.now()) {
  if (b.status === "held") return Date.parse(b.hold_expires_at || 0) > now;
  return ["pending_payment", "confirmed", "checked_in"].includes(b.status);
}

/** Allowed transitions (server-enforced). */
export const TRANSITIONS = {
  inquiry: ["held", "pending_payment", "confirmed", "cancelled"],
  held: ["pending_payment", "confirmed", "cancelled", "expired"],
  pending_payment: ["confirmed", "cancelled", "expired"],
  confirmed: ["checked_in", "cancelled", "no_show"],
  checked_in: ["checked_out"],
  checked_out: [],
  cancelled: [],
  expired: [],
  no_show: [],
};

export const SOURCES = {
  direct: "Bleiben Direct",
  airbnb: "Airbnb",
  booking_com: "Booking.com",
  makemytrip: "MakeMyTrip",
  goibibo: "Goibibo",
  agoda: "Agoda",
  phone: "Phone",
  whatsapp: "WhatsApp",
  walk_in: "Walk-in",
  manual: "Manual",
};
export const OFFLINE_SOURCES = ["phone", "whatsapp", "walk_in", "manual"];
export const PAYMENT_METHODS = ["cash", "upi", "card", "bank_transfer", "payment_link", "ota"];

export const bookingCode = () => `BLB-${crypto.randomBytes(3).toString("hex").toUpperCase()}`;

// ── Per-room lock: check-then-insert must not interleave ─────────────────────

const locks = new Map();

/** Runs `fn` while holding the lock for every key (sorted, so no deadlocks). */
export async function withLocks(keys, fn) {
  const sorted = [...new Set(keys.map(String))].sort();
  const releases = [];
  for (const key of sorted) {
    const prev = locks.get(key) || Promise.resolve();
    let release;
    const next = new Promise((r) => (release = r));
    locks.set(key, prev.then(() => next));
    await prev;
    releases.push(() => {
      release();
      if (locks.get(key) === next) locks.delete(key);
    });
  }
  try {
    return await fn();
  } finally {
    releases.reverse().forEach((r) => r());
  }
}

// ── Inventory reads ─────────────────────────────────────────────────────────

/** Active rooms of the org's properties (optionally one property). */
export async function orgRooms(db, orgId, propertyId) {
  const props = (await db.findDocs("properties", orgId == null ? {} : { org_id: orgId })).filter(
    (p) => p.status !== "deleted" && (propertyId == null || p.id === Number(propertyId)),
  );
  const out = [];
  for (const p of props) {
    const rooms = (await db.findDocs("rooms", { property_id: p.id })).filter((r) => r.status !== "archived");
    for (const r of rooms) out.push({ room: r, property: p });
  }
  return out;
}

export async function findRoom(db, orgId, roomId) {
  const room = await db.findDoc("rooms", { id: Number(roomId) });
  if (!room || room.status === "archived") return null;
  const property = await db.findDoc("properties", { id: room.property_id });
  if (!property || property.status === "deleted" || property.org_id !== orgId) return null;
  return { room, property };
}

const propertyPrice = (p) => Number(p.basePrice ?? p.base_price ?? 0);
export const roomBasePrice = (room, property) => Number(room.basePrice ?? propertyPrice(property));

/** Per-night snapshot for one room over [from, to). */
export async function roomNights(db, room, property, from, to) {
  const dates = nights(from, to);
  const set = new Set(dates);
  const blocks = (await db.findDocs("blocks", { room_id: room.id })).filter((b) => set.has(b.date));
  const rates = (await db.findDocs("rates", { room_id: room.id })).filter((r) => set.has(r.date));
  const bookings = (await db.findDocs("bookings", { room_id: room.id })).filter(
    (b) => occupies(b) && b.check_in < to && b.check_out > from,
  );
  const blockBy = new Map(blocks.map((b) => [b.date, b]));
  const rateBy = new Map(rates.map((r) => [r.date, r.price]));
  const base = roomBasePrice(room, property);
  return dates.map((date) => {
    const booked = bookings.filter((b) => b.check_in <= date && b.check_out > date).length;
    const block = blockBy.get(date);
    const units = room.unitCount ?? 1;
    return {
      date,
      price: rateBy.has(date) ? rateBy.get(date) : base,
      custom_price: rateBy.has(date),
      units,
      booked,
      blocked: Boolean(block),
      block_reason: block?.reason ?? null,
      block_notes: block?.notes ?? null,
      available: block ? 0 : Math.max(0, units - booked),
    };
  });
}

/**
 * Throws 409 with the conflicting nights unless one unit is free for every
 * night of the stay. `ignoreBookingId` lets an edit re-check its own dates.
 */
export async function assertAvailable(db, room, property, checkIn, checkOut, ignoreBookingId) {
  const snapshot = await roomNights(db, room, property, checkIn, checkOut);
  const own = ignoreBookingId ? await db.findDoc("bookings", { id: ignoreBookingId }) : null;
  const conflicts = snapshot.filter((n) => {
    const ownCounts = own && occupies(own) && own.room_id === room.id && own.check_in <= n.date && own.check_out > n.date;
    const free = n.blocked ? 0 : n.units - n.booked + (ownCounts ? 1 : 0);
    return free < 1;
  });
  if (conflicts.length) {
    throw new InputError(
      `${room.name} isn't available on ${conflicts.map((c) => c.date).join(", ")}`,
      409,
      { conflicts: conflicts.map((c) => ({ date: c.date, blocked: c.blocked, booked: c.booked, units: c.units })) },
    );
  }
  return snapshot;
}

/** Quote for a stay: nightly prices (calendar overrides win) + extra guests. */
export function quote(room, property, snapshot, guests) {
  const nightly = snapshot.map((n) => ({ date: n.date, price: n.price }));
  const stay = nightly.reduce((s, n) => s + n.price, 0);
  const included = Math.max(1, room.maxAdults ?? 2);
  const extraGuests = Math.max(0, (guests ?? 1) - included);
  const extraRate = Number(room.extraGuestCharge ?? property.extraGuestCharge ?? 0);
  const extra = extraGuests * extraRate * nightly.length;
  return { nights: nightly.length, nightly, stay, extra_guests: extraGuests, extra_guest_charge: extra, total: stay + extra };
}
