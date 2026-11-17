import crypto from "node:crypto";

import { Router } from "express";

import { InputError, SOURCES, addDays, bookingCode, findRoom, nowIso, occupies, orgRooms, roomNights, todayStr, withLocks } from "../bookings/core.js";
import { buildIcs, checkFeedUrl, fetchFeed, isBlockEvent, nightsToRanges, parseIcs } from "../channels/ical.js";
import { config } from "../config.js";
import { notify } from "../notify.js";
import { openSecret, sealSecret } from "../payments/gateway.js";

/**
 * Channel Manager — R1 iCal sync (MVP plan §2.7).
 * Import: each connection maps one external calendar (Airbnb, Booking.com,
 * Vrbo…) to a room. Reservations become imported bookings; owner blocks on
 * the OTA become external blocks (one unit). Our own dates echoed back by the
 * OTA are recognised and skipped. Events removed from the feed are cancelled.
 * Export: each room has a secret .ics link listing the nights it is sold out.
 * iCal is not instantaneous: feeds are polled (every 30 min, with retry backoff).
 */

export const CHANNELS = { airbnb: "Airbnb", booking_com: "Booking.com", vrbo: "Vrbo", agoda: "Agoda", makemytrip: "MakeMyTrip", ical: "Other calendar" };
const SYNC_EVERY_MIN = 30;
const backoffMin = (n) => Math.min(360, 5 * 2 ** Math.max(0, n - 1));

const handle = (fn) => async (req, res, next) => {
  try {
    if (req.scope?.org_id == null) throw new InputError("Choose an organisation (X-Org-Id) first");
    return await fn(req, res);
  } catch (err) {
    if (err instanceof InputError) return res.status(err.status).json({ detail: err.message, ...err.extra });
    return next(err);
  }
};

const nightsOf = (start, end) => {
  const out = [];
  for (let d = start; d < end; d = addDays(d, 1)) out.push(d);
  return out;
};

function publicConnection(c, room, property) {
  return {
    id: c.id,
    name: c.name,
    channel: c.channel,
    channel_label: CHANNELS[c.channel] ?? c.channel,
    room_id: c.room_id,
    room: room?.name ?? "(room removed)",
    property: property?.title ?? "",
    url_masked: c.url_masked,
    status: c.status,
    last_sync_at: c.last_sync_at,
    last_success_at: c.last_success_at,
    last_error: c.last_error,
    error_count: c.error_count ?? 0,
    next_sync_at: c.next_sync_at,
    stats: c.stats ?? null,
    created_at: c.created_at,
  };
}

const syncEvent = (conn, action, detail = "") => ({ at: nowIso(), by: `${CHANNELS[conn.channel] ?? "Calendar"} sync`, action, detail });

/** Nights (of `nights`) already closed on our side, ignoring this connection's own imports. */
async function closedNights(db, room, property, connId, start, end) {
  const snap = await roomNights(db, room, property, start, end);
  const mine = (await db.findDocs("bookings", { room_id: room.id })).filter((b) => b.connection_id === connId && occupies(b));
  return snap.filter((n) => {
    const own = mine.filter((b) => b.check_in <= n.date && b.check_out > n.date).length;
    return n.blocked || n.booked - own >= n.units;
  }).map((n) => n.date);
}

async function recordConflict(db, services, conn, booking, room, dates) {
  const others = (await db.findDocs("bookings", { room_id: room.id })).filter(
    (b) => b.id !== booking.id && occupies(b) && b.check_in < booking.check_out && b.check_out > booking.check_in,
  );
  const existing = await db.findDocs("sync_conflicts", { booking_id: booking.id });
  if (existing.some((c) => c.status === "open")) return null;
  const conflict = await db.insertDoc("sync_conflicts", {
    org_id: conn.org_id,
    room_id: room.id,
    property_id: room.property_id,
    connection_id: conn.id,
    booking_id: booking.id,
    channel: conn.channel,
    dates,
    overlapping: others.map((o) => ({ id: o.id, code: o.code, source: o.source, guest: o.guest?.name ?? "", check_in: o.check_in, check_out: o.check_out })),
    status: "open",
    created_at: nowIso(),
  });
  await notify(db, services, {
    orgId: conn.org_id,
    kind: "sync_conflict",
    guest: false,
    extra: {
      title: `Possible double booking · ${room.name}`,
      body: `${CHANNELS[conn.channel]} has a stay on ${dates.join(", ")} when ${room.name} was already full. Review it in Channel Manager → Conflicts.`,
      conflict_id: conflict.id,
    },
  });
  return conflict;
}

/** Runs one sync; never throws (errors are stored on the connection). */
export async function syncConnection(db, services, conn, fetchImpl = fetch) {
  const started = Date.now();
  const stats = { added: 0, updated: 0, removed: 0, skipped_echo: 0, conflicts: 0, events: 0 };
  try {
    const found = await findRoom(db, conn.org_id, conn.room_id);
    if (!found) throw new Error("The mapped room no longer exists. Map this calendar to another room.");
    const { room, property } = found;
    const events = parseIcs(await fetchFeed(openSecret(conn.url_sealed), fetchImpl)).filter((e) => e.status !== "CANCELLED");
    stats.events = events.length;
    const today = todayStr();
    const label = CHANNELS[conn.channel] ?? "Calendar";
    const source = SOURCES[conn.channel] ? conn.channel : "ical";

    await withLocks([`room:${room.id}`], async () => {
      const mine = (await db.findDocs("bookings", { room_id: room.id })).filter((b) => b.connection_id === conn.id);
      const byUid = new Map(mine.map((b) => [b.external_uid, b]));
      const seen = new Set();
      for (const e of events) {
        if (e.end <= today) continue; // history isn't imported
        seen.add(e.uid);
        const block = isBlockEvent(e);
        const ex = byUid.get(e.uid);
        const closed = await closedNights(db, room, property, conn.id, e.start, e.end);
        const all = nightsOf(e.start, e.end);
        if (block && closed.length === all.length) {
          // Our own sold-out dates echoed back by the OTA.
          stats.skipped_echo += 1;
          if (ex && occupies(ex)) {
            await db.updateDoc("bookings", { id: ex.id }, { status: "cancelled", cancel_reason: "Matches dates already closed in Bleiben", events: [...(ex.events ?? []), syncEvent(conn, "cancelled", "Echo of Bleiben dates")], updated_at: nowIso() });
          }
          continue;
        }
        const name = block ? `Blocked on ${label}` : !e.summary || /reserved|booked|reservation|not available/i.test(e.summary) ? `${label} guest` : e.summary.slice(0, 80);
        if (ex) {
          const reactivate = !occupies(ex);
          if (reactivate || ex.check_in !== e.start || ex.check_out !== e.end) {
            const updated = await db.updateDoc("bookings", { id: ex.id }, {
              check_in: e.start,
              check_out: e.end,
              status: "confirmed",
              cancel_reason: null,
              events: [...(ex.events ?? []), syncEvent(conn, "updated", `${e.start} → ${e.end}`)],
              updated_at: nowIso(),
            });
            stats.updated += 1;
            if (!block && closed.length) {
              if (await recordConflict(db, services, conn, updated, room, closed)) stats.conflicts += 1;
            }
          }
          continue;
        }
        const now = nowIso();
        const created = await db.insertDoc("bookings", {
          org_id: conn.org_id,
          property_id: property.id,
          room_id: room.id,
          code: bookingCode(),
          status: "confirmed",
          source,
          imported: true,
          external_block: block,
          connection_id: conn.id,
          external_uid: e.uid,
          check_in: e.start,
          check_out: e.end,
          guest: { name, phone: "", email: "" },
          adults: 1,
          children: 0,
          quote: null,
          total: 0,
          payments: [],
          paid: 0,
          notes: e.description ? e.description.slice(0, 500) : "",
          created_by: null,
          created_at: now,
          updated_at: now,
          events: [syncEvent(conn, block ? "blocked" : "imported", `${label} · ${e.start} → ${e.end}`)],
        });
        stats.added += 1;
        if (!block && closed.length) {
          if (await recordConflict(db, services, conn, created, room, closed)) stats.conflicts += 1;
        }
      }
      for (const b of mine) {
        if (seen.has(b.external_uid) || !occupies(b) || b.check_out <= today) continue;
        await db.updateDoc("bookings", { id: b.id }, { status: "cancelled", cancel_reason: `Removed from the ${label} calendar`, cancelled_at: nowIso(), events: [...(b.events ?? []), syncEvent(conn, "cancelled", `No longer in the ${label} calendar`)], updated_at: nowIso() });
        stats.removed += 1;
      }
    });

    const at = nowIso();
    await db.updateDoc("channel_connections", { id: conn.id }, {
      status: "active", last_sync_at: at, last_success_at: at, last_error: null, error_count: 0, stats,
      next_sync_at: new Date(Date.now() + SYNC_EVERY_MIN * 60000).toISOString(),
    });
    await db.insertDoc("sync_runs", { org_id: conn.org_id, connection_id: conn.id, status: "ok", ...stats, duration_ms: Date.now() - started, at });
    return { ok: true, ...stats };
  } catch (err) {
    const at = nowIso();
    const n = (conn.error_count ?? 0) + 1;
    const message = String(err?.message ?? err).slice(0, 300);
    await db.updateDoc("channel_connections", { id: conn.id }, {
      status: "error", last_sync_at: at, last_error: message, error_count: n,
      next_sync_at: new Date(Date.now() + backoffMin(n) * 60000).toISOString(),
    });
    await db.insertDoc("sync_runs", { org_id: conn.org_id, connection_id: conn.id, status: "error", error: message, ...stats, duration_ms: Date.now() - started, at });
    if (n === 1 || n === 5) {
      await notify(db, services, { orgId: conn.org_id, kind: "sync_error", guest: false, extra: { title: `Calendar sync failed · ${conn.name}`, body: message } });
    }
    return { ok: false, error: message };
  }
}

/** Scheduled worker: syncs every connection that is due. */
export async function syncDueConnections(db, services, fetchImpl = fetch) {
  const now = nowIso();
  for (const c of await db.findDocs("channel_connections", {})) {
    if (c.status === "disconnected") continue;
    if (c.next_sync_at && c.next_sync_at > now) continue;
    await syncConnection(db, services, c, fetchImpl);
  }
}

async function exportToken(db, orgId, roomId, regenerate = false) {
  const ex = await db.findDoc("ical_exports", { room_id: roomId });
  const token = crypto.randomBytes(24).toString("base64url");
  if (ex && !regenerate) return ex.token;
  if (ex) await db.updateDoc("ical_exports", { id: ex.id }, { token, updated_at: nowIso() });
  else await db.insertDoc("ical_exports", { org_id: orgId, room_id: roomId, token, created_at: nowIso() });
  return token;
}

const exportUrl = (token) => `${config.apiBaseUrl}/api/ical/${token}.ics`;

/** Public: GET /api/ical/:token.ics — nights the room is closed (sold out or blocked). */
export function icalExportRouter(db) {
  const router = Router();
  router.get("/:file", async (req, res, next) => {
    try {
      const token = String(req.params.file).replace(/\.ics$/, "");
      const ex = await db.findDoc("ical_exports", { token });
      if (!ex) return res.status(404).send("Not found");
      const found = await findRoom(db, ex.org_id, ex.room_id);
      if (!found) return res.status(404).send("Not found");
      const { room, property } = found;
      const from = addDays(todayStr(), -7);
      const snap = await roomNights(db, room, property, from, addDays(todayStr(), 365));
      const closed = snap.filter((n) => n.available < 1).map((n) => n.date);
      const ranges = nightsToRanges(closed).map((r) => ({ ...r, summary: "Not available", uid: `${room.id}-${r.start}-${r.end}@bleiben` }));
      res.setHeader("Content-Type", "text/calendar; charset=utf-8");
      res.setHeader("Cache-Control", "no-store");
      return res.send(buildIcs(`${property.title} · ${room.name}`, ranges));
    } catch (err) {
      return next(err);
    }
  });
  return router;
}

export function channelsRouter(db, services = {}) {
  const router = Router();
  const fetchImpl = services.fetch ?? fetch;

  async function scoped(req) {
    const c = await db.findDoc("channel_connections", { id: Number(req.params.id) });
    if (!c || c.org_id !== req.scope.org_id) throw new InputError("Connection not found", 404);
    return c;
  }

  async function view(c) {
    const room = await db.findDoc("rooms", { id: c.room_id });
    const property = room ? await db.findDoc("properties", { id: room.property_id }) : null;
    return publicConnection(c, room, property);
  }

  router.get("/", handle(async (req, res) => {
    const conns = (await db.findDocs("channel_connections", { org_id: req.scope.org_id })).filter((c) => c.status !== "disconnected");
    const out = [];
    for (const c of conns.sort((a, b) => a.id - b.id)) out.push(await view(c));
    const exports = [];
    for (const { room, property } of await orgRooms(db, req.scope.org_id)) {
      exports.push({ room_id: room.id, room: room.name, property: property.title || "Untitled property", units: room.unitCount ?? 1, url: exportUrl(await exportToken(db, req.scope.org_id, room.id)) });
    }
    const conflicts = (await db.findDocs("sync_conflicts", { org_id: req.scope.org_id })).filter((c) => c.status === "open").length;
    return res.json({ connections: out, exports, open_conflicts: conflicts, channels: CHANNELS, sync_every_minutes: SYNC_EVERY_MIN });
  }));

  function validChannel(v) {
    const ch = String(v ?? "ical");
    if (!CHANNELS[ch]) throw new InputError(`Channel must be one of: ${Object.keys(CHANNELS).join(", ")}`);
    return ch;
  }

  // Connect: validate the link (download + parse), save, run the first sync.
  router.post("/", handle(async (req, res) => {
    const channel = validChannel(req.body?.channel);
    const found = await findRoom(db, req.scope.org_id, req.body?.room_id);
    if (!found) throw new InputError("Choose the room this calendar belongs to");
    let url;
    let events;
    try {
      url = await checkFeedUrl(req.body?.url);
      events = parseIcs(await fetchFeed(url, fetchImpl));
    } catch (err) {
      throw new InputError(err.message);
    }
    const dup = (await db.findDocs("channel_connections", { org_id: req.scope.org_id })).find((c) => c.status !== "disconnected" && openSecret(c.url_sealed) === url);
    if (dup) throw new InputError("This calendar link is already connected");
    const name = String(req.body?.name ?? "").trim().slice(0, 60) || `${CHANNELS[channel]} · ${found.room.name}`;
    const c = await db.insertDoc("channel_connections", {
      org_id: req.scope.org_id,
      room_id: found.room.id,
      property_id: found.property.id,
      name,
      channel,
      url_sealed: sealSecret(url),
      url_masked: `${new URL(url).host}/…${url.slice(-6)}`,
      status: "active",
      error_count: 0,
      created_by: req.user.id,
      created_at: nowIso(),
    });
    const result = await syncConnection(db, services, c, fetchImpl);
    return res.status(201).json({ ...(await view(await db.findDoc("channel_connections", { id: c.id }))), first_sync: result, events_found: events.length });
  }));

  router.patch("/:id", handle(async (req, res) => {
    const c = await scoped(req);
    const set = {};
    if (req.body?.name !== undefined) set.name = String(req.body.name).trim().slice(0, 60) || c.name;
    if (req.body?.channel !== undefined) set.channel = validChannel(req.body.channel);
    if (req.body?.room_id !== undefined) {
      const found = await findRoom(db, req.scope.org_id, req.body.room_id);
      if (!found) throw new InputError("Choose the room this calendar belongs to");
      if (found.room.id !== c.room_id) {
        // Moving the mapping: release imports from the old room; the next sync re-imports.
        for (const b of (await db.findDocs("bookings", { room_id: c.room_id })).filter((x) => x.connection_id === c.id && occupies(x))) {
          await db.updateDoc("bookings", { id: b.id }, { status: "cancelled", cancel_reason: "Calendar mapped to another room", updated_at: nowIso() });
        }
      }
      Object.assign(set, { room_id: found.room.id, property_id: found.property.id });
    }
    if (req.body?.url !== undefined) {
      try {
        const url = await checkFeedUrl(req.body.url);
        parseIcs(await fetchFeed(url, fetchImpl));
        Object.assign(set, { url_sealed: sealSecret(url), url_masked: `${new URL(url).host}/…${url.slice(-6)}` });
      } catch (err) {
        throw new InputError(err.message);
      }
    }
    const updated = await db.updateDoc("channel_connections", { id: c.id }, { ...set, updated_at: nowIso() });
    if (set.room_id || set.url_sealed) await syncConnection(db, services, updated, fetchImpl);
    return res.json(await view(await db.findDoc("channel_connections", { id: c.id })));
  }));

  // Disconnect: stop syncing and release future imported dates.
  router.delete("/:id", handle(async (req, res) => {
    const c = await scoped(req);
    let released = 0;
    for (const b of (await db.findDocs("bookings", { room_id: c.room_id })).filter((x) => x.connection_id === c.id && occupies(x) && x.check_out > todayStr())) {
      await db.updateDoc("bookings", { id: b.id }, { status: "cancelled", cancel_reason: `${c.name} disconnected`, cancelled_at: nowIso(), updated_at: nowIso() });
      released += 1;
    }
    await db.updateDoc("channel_connections", { id: c.id }, { status: "disconnected", disconnected_at: nowIso() });
    return res.json({ disconnected: true, released });
  }));

  // Manual sync / retry.
  router.post("/:id/sync", handle(async (req, res) => {
    const c = await scoped(req);
    if (c.status === "disconnected") throw new InputError("This calendar is disconnected");
    const result = await syncConnection(db, services, c, fetchImpl);
    return res.json({ ...result, connection: await view(await db.findDoc("channel_connections", { id: c.id })) });
  }));

  router.get("/:id/history", handle(async (req, res) => {
    const c = await scoped(req);
    const runs = (await db.findDocs("sync_runs", { connection_id: c.id })).sort((a, b) => b.id - a.id).slice(0, 50);
    return res.json(runs);
  }));

  router.get("/conflicts/list", handle(async (req, res) => {
    const status = String(req.query.status ?? "open");
    const list = (await db.findDocs("sync_conflicts", { org_id: req.scope.org_id })).filter((c) => status === "all" || c.status === status).sort((a, b) => b.id - a.id);
    const out = [];
    for (const c of list) {
      const b = await db.findDoc("bookings", { id: c.booking_id });
      const room = await db.findDoc("rooms", { id: c.room_id });
      const property = await db.findDoc("properties", { id: c.property_id });
      out.push({
        ...c,
        channel_label: CHANNELS[c.channel] ?? c.channel,
        room: room?.name ?? "",
        property: property?.title ?? "",
        booking: b ? { id: b.id, code: b.code, status: b.status, check_in: b.check_in, check_out: b.check_out, guest: b.guest?.name ?? "" } : null,
      });
    }
    return res.json(out);
  }));

  router.post("/conflicts/:cid/resolve", handle(async (req, res) => {
    const c = await db.findDoc("sync_conflicts", { id: Number(req.params.cid) });
    if (!c || c.org_id !== req.scope.org_id) throw new InputError("Conflict not found", 404);
    if (c.status !== "open") throw new InputError("Already resolved");
    const note = String(req.body?.note ?? "").trim().slice(0, 300);
    if (note.length < 3) throw new InputError("Add a short note on how this was resolved");
    const updated = await db.updateDoc("sync_conflicts", { id: c.id }, { status: "resolved", resolution: note, resolved_by: req.user.name || req.user.email, resolved_at: nowIso() });
    return res.json(updated);
  }));

  router.post("/exports/:roomId/regenerate", handle(async (req, res) => {
    const found = await findRoom(db, req.scope.org_id, req.params.roomId);
    if (!found) throw new InputError("Room not found", 404);
    return res.json({ room_id: found.room.id, url: exportUrl(await exportToken(db, req.scope.org_id, found.room.id, true)) });
  }));

  return router;
}

