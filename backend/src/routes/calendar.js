import { Router } from "express";

import {
  InputError,
  addDays,
  findRoom,
  nights,
  nowIso,
  occupies,
  orgRooms,
  requireRange,
  roomBasePrice,
  roomNights,
  todayStr,
  toDate,
  withLocks,
} from "../bookings/core.js";

const handle = (fn) => async (req, res, next) => {
  try {
    if (req.scope?.org_id == null) throw new InputError("Choose an organisation (X-Org-Id) first");
    return await fn(req, res);
  } catch (err) {
    if (err instanceof InputError) return res.status(err.status).json({ detail: err.message, ...err.extra });
    return next(err);
  }
};

const MAX_DAYS = 62;

/** Validates room ids belong to the org; returns [{room, property}]. */
async function resolveRooms(db, orgId, ids) {
  if (!Array.isArray(ids) || ids.length === 0) throw new InputError("Select at least one room");
  const out = [];
  for (const id of ids) {
    const found = await findRoom(db, orgId, id);
    if (!found) throw new InputError(`Room ${id} not found`, 404);
    out.push(found);
  }
  return out;
}

/** Inclusive date range from the body ("block 21–25 Jul" = 5 nights), filtered by weekday. */
function selectedDates(body) {
  const from = body?.from;
  const to = body?.to ?? from;
  if (!toDate(from) || !toDate(to)) throw new InputError("Pick a date range");
  if (toDate(to) < toDate(from)) throw new InputError("The end date is before the start date");
  const all = nights(from, addDays(to, 1));
  if (all.length > 366) throw new InputError("That range is too long (max 366 days)");
  const days = Array.isArray(body?.days_of_week) && body.days_of_week.length ? new Set(body.days_of_week.map(Number)) : null;
  const picked = days ? all.filter((d) => days.has(toDate(d).getUTCDay())) : all;
  if (!picked.length) throw new InputError("No dates match the selected days");
  return picked;
}

const bookingBar = (b) => ({
  id: b.id,
  code: b.code,
  guest_name: b.guest?.name ?? "",
  guests: (b.adults ?? 1) + (b.children ?? 0),
  source: b.source,
  status: b.status,
  check_in: b.check_in,
  check_out: b.check_out,
  balance: Math.max(0, (b.total ?? 0) - (b.paid ?? 0)),
});

/**
 * Unified calendar (MVP §2 / homyhuts Calendar): properties → rooms →
 * per-night price, availability, blocks, plus booking bars.
 */
export function calendarRouter(db) {
  const router = Router();

  router.get(
    "/",
    handle(async (req, res) => {
      const from = toDate(req.query.from) ? req.query.from : todayStr();
      const days = Math.min(MAX_DAYS, Math.max(1, Number(req.query.days) || 15));
      const to = addDays(from, days);
      const q = String(req.query.search ?? "").trim().toLowerCase();
      const rooms = await orgRooms(db, req.scope.org_id, req.query.property_id);
      const byProperty = new Map();
      for (const { room, property } of rooms) {
        const hay = [property.title, property.propertySerialId, property.address?.city, room.name].join(" ").toLowerCase();
        if (q && !hay.includes(q)) continue;
        if (!byProperty.has(property.id)) {
          byProperty.set(property.id, {
            id: property.id,
            serial_id: property.propertySerialId,
            title: property.title || "Untitled property",
            city: property.address?.city ?? "",
            status: property.status,
            rooms: [],
          });
        }
        const cells = await roomNights(db, room, property, from, to);
        const bars = (await db.findDocs("bookings", { room_id: room.id }))
          .filter((b) => (occupies(b) || ["checked_out", "no_show"].includes(b.status)) && b.check_in < to && b.check_out > from)
          .map(bookingBar);
        const sellable = cells.reduce((n, c) => n + (c.blocked ? 0 : c.units), 0);
        const sold = cells.reduce((n, c) => n + Math.min(c.booked, c.units), 0);
        byProperty.get(property.id).rooms.push({
          id: room.id,
          name: room.name,
          room_type: room.roomType,
          units: room.unitCount ?? 1,
          max_guests: (room.maxAdults ?? 2) + (room.maxChildren ?? 0),
          base_price: roomBasePrice(room, property),
          occupancy: sellable ? Math.round((sold / sellable) * 100) : 0,
          cells,
          bookings: bars,
        });
      }
      const properties = [...byProperty.values()];
      return res.json({
        from,
        to,
        days: nights(from, to),
        total_properties: new Set(rooms.map((r) => r.property.id)).size,
        properties,
      });
    }),
  );

  // Block dates: one doc per room per night; re-blocking updates the reason.
  router.post(
    "/blocks",
    handle(async (req, res) => {
      const targets = await resolveRooms(db, req.scope.org_id, req.body?.room_ids);
      const dates = selectedDates(req.body);
      const reason = String(req.body?.reason ?? "").trim().slice(0, 120) || "Blocked";
      const notes = String(req.body?.notes ?? "").trim().slice(0, 500);
      let count = 0;
      await withLocks(targets.map((t) => `room:${t.room.id}`), async () => {
        for (const { room } of targets) {
          for (const date of dates) {
            const existing = await db.findDoc("blocks", { room_id: room.id, date });
            if (existing) await db.updateDoc("blocks", { id: existing.id }, { reason, notes, updated_at: nowIso() });
            else {
              await db.insertDoc("blocks", {
                org_id: req.scope.org_id,
                property_id: room.property_id,
                room_id: room.id,
                date,
                reason,
                notes,
                created_by: req.user.id,
                created_at: nowIso(),
              });
            }
            count += 1;
          }
        }
      });
      return res.status(201).json({ blocked: count, dates: dates.length, rooms: targets.length });
    }),
  );

  // Unblock (open) dates.
  router.post(
    "/unblock",
    handle(async (req, res) => {
      const targets = await resolveRooms(db, req.scope.org_id, req.body?.room_ids);
      const dates = new Set(selectedDates(req.body));
      let removed = 0;
      for (const { room } of targets) {
        for (const b of await db.findDocs("blocks", { room_id: room.id })) {
          if (dates.has(b.date)) removed += await db.deleteDocs("blocks", { id: b.id });
        }
      }
      return res.json({ opened: removed });
    }),
  );

  // Edit the reason/notes of existing blocks (per range or "overwrite all").
  router.patch(
    "/blocks",
    handle(async (req, res) => {
      const targets = await resolveRooms(db, req.scope.org_id, req.body?.room_ids);
      const dates = new Set(selectedDates(req.body));
      const set = {};
      if (req.body?.reason !== undefined) set.reason = String(req.body.reason).trim().slice(0, 120) || "Blocked";
      if (req.body?.notes !== undefined) set.notes = String(req.body.notes).trim().slice(0, 500);
      let updated = 0;
      for (const { room } of targets) {
        for (const b of await db.findDocs("blocks", { room_id: room.id })) {
          if (dates.has(b.date)) {
            await db.updateDoc("blocks", { id: b.id }, { ...set, updated_at: nowIso() });
            updated += 1;
          }
        }
      }
      return res.json({ updated });
    }),
  );

  // Pricing: set a nightly price, or adjust by % (Flexi Pricing) — selected weekdays only.
  router.put(
    "/rates",
    handle(async (req, res) => {
      const targets = await resolveRooms(db, req.scope.org_id, req.body?.room_ids);
      const dates = selectedDates(req.body);
      const hasPrice = req.body?.price !== undefined && req.body?.price !== null && req.body?.price !== "";
      const hasPercent = req.body?.percent !== undefined && req.body?.percent !== null && req.body?.percent !== "";
      if (hasPrice === hasPercent) throw new InputError("Send either a price or a percentage");
      const price = hasPrice ? Number(req.body.price) : null;
      const percent = hasPercent ? Number(req.body.percent) : null;
      if (hasPrice && (!Number.isFinite(price) || price <= 0 || price > 10_000_000)) throw new InputError("Enter a nightly price above 0");
      if (hasPercent && (!Number.isFinite(percent) || percent < -90 || percent > 500 || percent === 0)) {
        throw new InputError("Adjust by a percentage between -90 and 500");
      }
      const minPrice = req.body?.min_price != null ? Number(req.body.min_price) : 0;
      let updated = 0;
      for (const { room, property } of targets) {
        const snapshot = hasPercent ? await roomNights(db, room, property, dates[0], addDays(dates.at(-1), 1)) : [];
        const current = new Map(snapshot.map((n) => [n.date, n.price]));
        for (const date of dates) {
          let next = price;
          if (hasPercent) next = Math.max(minPrice, Math.round((current.get(date) ?? roomBasePrice(room, property)) * (1 + percent / 100)));
          if (!(next > 0)) continue;
          const existing = await db.findDoc("rates", { room_id: room.id, date });
          if (existing) await db.updateDoc("rates", { id: existing.id }, { price: next, updated_at: nowIso() });
          else await db.insertDoc("rates", { org_id: req.scope.org_id, room_id: room.id, property_id: room.property_id, date, price: next, created_at: nowIso() });
          updated += 1;
        }
      }
      return res.json({ updated });
    }),
  );

  // Room availability for a stay (used by Create Booking).
  router.get(
    "/availability",
    handle(async (req, res) => {
      const { room_id: roomId, check_in: checkIn, check_out: checkOut } = req.query;
      requireRange(checkIn, checkOut);
      const found = await findRoom(db, req.scope.org_id, roomId);
      if (!found) throw new InputError("Room not found", 404);
      const cells = await roomNights(db, found.room, found.property, checkIn, checkOut);
      return res.json({
        available: cells.every((c) => c.available >= 1),
        min_available: Math.min(...cells.map((c) => c.available)),
        nights: cells,
      });
    }),
  );

  return router;
}
