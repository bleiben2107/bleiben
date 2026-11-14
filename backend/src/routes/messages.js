import { Router } from "express";

import { InputError, SOURCES, addDays, nights, nowIso, todayStr } from "../bookings/core.js";
import { can } from "../roles.js";

/**
 * Inbox / Messages (REA 08 §5, Bleiben side). One conversation per booking,
 * created on demand. Hosts log what the guest sent (phone / WhatsApp / OTA)
 * and record replies — Bleiben has no guest channel connected yet, so
 * outgoing messages are recorded, not delivered. Stars, priority, read state
 * and archive are per user ("yours alone"). Scheduled messages are held if
 * the booking changes or is cancelled before they go out.
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

const byName = (req) => req.user.name || req.user.email || `user ${req.user.id}`;
const MAX_BODY = 4000;

/** Starter quick replies (shared). Variables in {braces} are filled per conversation. */
export const STARTER_REPLIES = [
  { shortcut: "welcome", title: "Booking confirmed", body: "Hi {guest_first_name}, thanks for booking {property_name}! We look forward to hosting you on {check_in} ({nights} night(s), {guests} guest(s)). — {host_name}" },
  { shortcut: "early", title: "Early check-in", body: "Hi {guest_first_name}, check-in is from {check_in_time}. We'll try to have the room ready earlier and will let you know on the day." },
  { shortcut: "directions", title: "Directions", body: "Here's how to reach {property_name}: {map_link}. Our caretaker {caretaker_name} ({caretaker_phone}) will help you on arrival." },
  { shortcut: "checkin", title: "Check-in details", body: "Check-in: {check_in} from {check_in_time}. Check-out: {check_out} by {check_out_time}. Check-in method: {check_in_method}." },
  { shortcut: "rules", title: "House rules", body: "A few house rules for your stay: {house_rules}. Max guests: {max_guests}." },
  { shortcut: "cancel", title: "Cancellation policy", body: "Our cancellation policy is {cancellation_policy}." },
  { shortcut: "taken", title: "Dates taken", body: "Sorry {guest_first_name}, those dates are taken. The nearest free dates are {nearest_free_dates}." },
];

export const TEMPLATE_VARIABLES = [
  "guest_first_name", "guest_name", "check_in", "check_out", "nights", "guests", "property_name", "property_description",
  "map_link", "check_in_time", "check_out_time", "check_in_method", "caretaker_name", "caretaker_phone", "house_rules",
  "max_guests", "cancellation_policy", "host_name", "nearest_free_dates",
];

const METHOD_LABELS = { host_greets: "the host greets you", self_check_in: "self check-in", lockbox: "lockbox", smart_lock: "smart lock", caretaker: "the caretaker greets you" };
const STAGES = ["upcoming", "ongoing", "completed", "cancelled"];

const pretty = (d) => {
  if (!d) return "";
  const [y, m, day] = d.split("-").map(Number);
  return `${day} ${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][m - 1]} ${y}`;
};

function stageOf(b) {
  if (!b) return "upcoming";
  if (["cancelled", "expired", "no_show"].includes(b.status)) return "cancelled";
  if (b.status === "checked_out") return "completed";
  const t = todayStr();
  if (b.status === "checked_in" || (b.check_in <= t && b.check_out > t)) return "ongoing";
  if (b.check_out <= t) return "completed";
  return "upcoming";
}

/** Fingerprint of what a scheduled message was written for. */
const bookingKey = (b) => (b ? `${b.status === "checked_in" || b.status === "checked_out" ? "confirmed" : b.status}|${b.check_in}|${b.check_out}|${b.room_id}` : "");

async function nearestFreeDates(db, b) {
  if (!b) return "";
  const room = await db.findDoc("rooms", { id: b.room_id });
  if (!room) return "";
  const units = room.unitCount ?? 1;
  const len = Math.max(1, nights(b.check_in, b.check_out).length);
  const all = await db.findDocs("bookings", { room_id: room.id });
  const blocks = new Set((await db.findDocs("blocks", { room_id: room.id })).map((x) => x.date));
  const free = (d) => !blocks.has(d) && all.filter((o) => o.id !== b.id && ["held", "pending_payment", "confirmed", "checked_in"].includes(o.status) && o.check_in <= d && o.check_out > d).length < units;
  let start = todayStr() > b.check_in ? todayStr() : b.check_in;
  for (let i = 0; i < 120; i++, start = addDays(start, 1)) {
    let ok = true;
    for (let k = 0; k < len && ok; k++) ok = free(addDays(start, k));
    if (ok) return `${pretty(start)} – ${pretty(addDays(start, len))}`;
  }
  return "";
}

export async function fillTemplate(db, body, { thread, booking, property, req }) {
  const needsFree = body.includes("{nearest_free_dates}");
  const rules = property?.houseRules ?? {};
  const ruleText = [
    rules.smokingAllowed === false && "no smoking",
    rules.partiesAllowed === false && "no parties",
    rules.petsAllowed === false && "no pets",
    rules.additionalRules,
  ].filter(Boolean).join(", ");
  const addr = property?.address?.formattedAddress || [property?.address?.city, property?.address?.state].filter(Boolean).join(", ");
  const vars = {
    guest_first_name: String(thread.guest_name ?? "").split(" ")[0],
    guest_name: thread.guest_name ?? "",
    check_in: pretty(booking?.check_in),
    check_out: pretty(booking?.check_out),
    nights: booking ? String(nights(booking.check_in, booking.check_out).length) : "",
    guests: booking ? String((booking.adults ?? 1) + (booking.children ?? 0)) : "",
    property_name: property?.title ?? "",
    property_description: property?.description ?? "",
    map_link: addr ? `https://maps.google.com/?q=${encodeURIComponent(addr)}` : "",
    check_in_time: property?.checkInTime || "the usual time",
    check_out_time: property?.checkOutTime || "the usual time",
    check_in_method: METHOD_LABELS[property?.checkInMethod] ?? property?.checkInMethod ?? "",
    caretaker_name: property?.caretaker?.name ?? "",
    caretaker_phone: property?.caretaker?.phone ?? "",
    house_rules: ruleText || "none",
    max_guests: String(property?.capacity?.guests ?? ""),
    cancellation_policy: property?.cancellationPolicy ?? "",
    host_name: req.user.name ?? "",
    nearest_free_dates: needsFree ? await nearestFreeDates(db, booking) : "",
  };
  return body.replace(/\{(\w+)\}/g, (m, k) => (Object.hasOwn(vars, k) ? vars[k] : m));
}

/** Creates a conversation for every booking that doesn't have one yet. */
async function syncThreads(db, orgId) {
  const bookings = await db.findDocs("bookings", { org_id: orgId });
  const threads = await db.findDocs("threads", { org_id: orgId });
  const have = new Set(threads.map((t) => t.booking_id));
  for (const b of bookings) {
    if (have.has(b.id)) continue;
    await db.insertDoc("threads", {
      org_id: orgId,
      booking_id: b.id,
      property_id: b.property_id,
      channel: b.source,
      guest_name: b.guest?.name ?? "Guest",
      messages: [],
      note: null,
      user_state: {},
      last_message_at: b.created_at,
      created_at: b.created_at,
    });
  }
}

/** Sends due scheduled messages; holds those whose booking changed. */
export async function dispatchScheduled(db, now = nowIso()) {
  const due = (await db.findDocs("scheduled_messages", { status: "scheduled" })).filter((s) => s.send_at <= now);
  for (const s of due) {
    const thread = await db.findDoc("threads", { id: s.thread_id });
    const booking = thread?.booking_id ? await db.findDoc("bookings", { id: thread.booking_id }) : null;
    if (!thread) {
      await db.updateDoc("scheduled_messages", { id: s.id }, { status: "cancelled" });
      continue;
    }
    if (bookingKey(booking) !== s.booking_key) {
      await db.updateDoc("scheduled_messages", { id: s.id }, { status: "held", held_reason: booking && ["cancelled", "expired", "no_show"].includes(booking.status) ? "The booking was cancelled" : "The booking changed after this was scheduled" });
      continue;
    }
    const msg = { id: `${s.id}-s`, direction: "out", body: s.body, at: now, by: s.by_name, by_id: s.by_id, scheduled: true, delivery: "recorded" };
    await db.updateDoc("threads", { id: thread.id }, { messages: [...thread.messages, msg], last_message_at: now });
    await db.updateDoc("scheduled_messages", { id: s.id }, { status: "sent", sent_at: now });
  }
}

function stateFor(t, userId) {
  return t.user_state?.[userId] ?? { read_at: null, starred: false, priority: false, archived: false };
}

function waiting(t) {
  const last = t.messages.at(-1);
  return last?.direction === "in" ? last.at : null;
}

function unread(t, userId) {
  const st = stateFor(t, userId);
  return t.messages.some((m) => m.direction === "in" && (!st.read_at || m.at > st.read_at));
}

export function messagesRouter(db) {
  const router = Router();

  async function scoped(req) {
    const t = await db.findDoc("threads", { id: Number(req.params.id) });
    if (!t || t.org_id !== req.scope.org_id) throw new InputError("Conversation not found", 404);
    return t;
  }

  async function context(t) {
    const booking = t.booking_id ? await db.findDoc("bookings", { id: t.booking_id }) : null;
    const property = await db.findDoc("properties", { id: t.property_id });
    return { booking, property };
  }

  function summary(t, booking, property, userId) {
    const st = stateFor(t, userId);
    const last = t.messages.at(-1);
    return {
      id: t.id,
      guest_name: t.guest_name,
      channel: t.channel,
      channel_label: SOURCES[t.channel] ?? t.channel,
      property: { id: t.property_id, title: property?.title || "Untitled property" },
      booking: booking ? { id: booking.id, code: booking.code, status: booking.status, check_in: booking.check_in, check_out: booking.check_out } : null,
      stage: stageOf(booking),
      last_message: last ? { body: last.body.slice(0, 140), direction: last.direction, at: last.at } : null,
      last_message_at: t.last_message_at,
      waiting_since: waiting(t),
      unread: unread(t, userId),
      starred: st.starred,
      priority: st.priority,
      archived: st.archived,
    };
  }

  router.get(
    "/",
    handle(async (req, res) => {
      await syncThreads(db, req.scope.org_id);
      await dispatchScheduled(db);
      const uid = req.user.id;
      const q = String(req.query.q ?? "").trim().toLowerCase();
      const view = req.query.view ?? "all";
      const out = [];
      for (const t of await db.findDocs("threads", { org_id: req.scope.org_id })) {
        const { booking, property } = await context(t);
        const s = summary(t, booking, property, uid);
        if (view === "archived" ? !s.archived : s.archived) continue;
        if (view === "starred" && !s.starred) continue;
        if (req.query.unread === "true" && !s.unread) continue;
        if (req.query.channel && req.query.channel !== "all" && s.channel !== req.query.channel) continue;
        if (req.query.property_id && s.property.id !== Number(req.query.property_id)) continue;
        if (req.query.stage && req.query.stage !== "any" && s.stage !== req.query.stage) continue;
        if (q.length >= 2 && ![s.guest_name, s.property.title, s.booking?.code, ...t.messages.map((m) => m.body)].join(" ").toLowerCase().includes(q)) continue;
        out.push(s);
      }
      // Waiting on you, most urgent first: priority, then longest-waiting guest, then latest activity.
      out.sort((a, b) => {
        if (a.priority !== b.priority) return a.priority ? -1 : 1;
        if (!!a.waiting_since !== !!b.waiting_since) return a.waiting_since ? -1 : 1;
        if (a.waiting_since && b.waiting_since) return a.waiting_since < b.waiting_since ? -1 : 1;
        return (a.last_message_at ?? "") < (b.last_message_at ?? "") ? 1 : -1;
      });
      return res.json({ items: out, total: out.length, stages: STAGES, channels: SOURCES });
    }),
  );

  router.get(
    "/unread-count",
    handle(async (req, res) => {
      await syncThreads(db, req.scope.org_id);
      const list = await db.findDocs("threads", { org_id: req.scope.org_id });
      return res.json({ count: list.filter((t) => !stateFor(t, req.user.id).archived && unread(t, req.user.id)).length });
    }),
  );

  // Reply times: from each guest message to the next host reply.
  router.get(
    "/reply-times",
    handle(async (req, res) => {
      const days = { today: 1, "7d": 7, "30d": 30 }[req.query.range ?? "7d"] ?? 7;
      // Window starts at IST midnight; message times are UTC instants.
      const since = new Date(`${addDays(todayStr(), -(days - 1))}T00:00:00+05:30`).toISOString();
      const gaps = [];
      for (const t of await db.findDocs("threads", { org_id: req.scope.org_id })) {
        let waitingFrom = null;
        for (const m of t.messages) {
          if (m.direction === "in") waitingFrom ??= m.at;
          else if (waitingFrom) {
            if (m.at >= since) gaps.push({ minutes: (Date.parse(m.at) - Date.parse(waitingFrom)) / 60000, agent: m.by, agent_id: m.by_id });
            waitingFrom = null;
          }
        }
      }
      const stats = (list) => {
        if (!list.length) return { replies: 0, typical_minutes: null, average_minutes: null, within_hour: null };
        const sorted = list.map((g) => g.minutes).sort((a, b) => a - b);
        const mid = Math.floor(sorted.length / 2);
        const median = sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
        return {
          replies: list.length,
          typical_minutes: Math.round(median),
          average_minutes: Math.round(sorted.reduce((s, v) => s + v, 0) / sorted.length),
          within_hour: Math.round((sorted.filter((v) => v <= 60).length / sorted.length) * 100),
        };
      };
      const agents = new Map();
      for (const g of gaps) agents.set(g.agent, [...(agents.get(g.agent) ?? []), g]);
      // Agent figures: host and full-access members only.
      const full = can(req.membership?.role, "messages.write");
      return res.json({
        range: req.query.range ?? "7d",
        ...stats(gaps),
        by_agent: full ? [...agents.entries()].map(([agent, list]) => ({ agent, ...stats(list) })) : [],
      });
    }),
  );

  router.get("/quick-replies", handle(async (req, res) => {
    const own = (await db.findDocs("quick_replies", { org_id: req.scope.org_id, user_id: req.user.id })).map((r) => ({ ...r, own: true }));
    return res.json({ starter: STARTER_REPLIES, own, variables: TEMPLATE_VARIABLES });
  }));

  function validReply(body) {
    const shortcut = String(body?.shortcut ?? "").trim().toLowerCase().replace(/[^a-z0-9_-]/g, "").slice(0, 20);
    const title = String(body?.title ?? "").trim().slice(0, 80);
    const text = String(body?.body ?? "").trim().slice(0, MAX_BODY);
    if (!shortcut || !title || !text) throw new InputError("Add a shortcut, a title and the reply text");
    return { shortcut, title, body: text };
  }

  router.post("/quick-replies", handle(async (req, res) => {
    const r = validReply(req.body);
    const mine = await db.findDocs("quick_replies", { org_id: req.scope.org_id, user_id: req.user.id });
    if (mine.some((x) => x.shortcut === r.shortcut) || STARTER_REPLIES.some((x) => x.shortcut === r.shortcut)) throw new InputError("That shortcut is taken");
    const saved = await db.insertDoc("quick_replies", { org_id: req.scope.org_id, user_id: req.user.id, ...r, created_at: nowIso() });
    return res.status(201).json(saved);
  }));

  async function ownReply(req) {
    const r = await db.findDoc("quick_replies", { id: Number(req.params.rid) });
    if (!r || r.org_id !== req.scope.org_id || r.user_id !== req.user.id) throw new InputError("Quick reply not found", 404);
    return r;
  }

  router.patch("/quick-replies/:rid", handle(async (req, res) => {
    const r = await ownReply(req);
    return res.json(await db.updateDoc("quick_replies", { id: r.id }, validReply({ ...r, ...req.body })));
  }));

  router.delete("/quick-replies/:rid", handle(async (req, res) => {
    const r = await ownReply(req);
    await db.deleteDocs("quick_replies", { id: r.id });
    return res.json({ deleted: true });
  }));

  router.get(
    "/:id",
    handle(async (req, res) => {
      await dispatchScheduled(db);
      const t = await scoped(req);
      const { booking, property } = await context(t);
      const scheduled = (await db.findDocs("scheduled_messages", { thread_id: t.id })).filter((s) => ["scheduled", "held"].includes(s.status));
      const paid = (booking?.payments ?? []).reduce((s, p) => s + (p.kind === "refund" ? -p.amount : p.amount), 0);
      return res.json({
        ...summary(t, booking, property, req.user.id),
        messages: t.messages,
        note: t.note,
        scheduled: scheduled.sort((a, b) => (a.send_at < b.send_at ? -1 : 1)),
        details: booking
          ? {
              guest: booking.guest,
              adults: booking.adults,
              children: booking.children,
              nights: nights(booking.check_in, booking.check_out).length,
              room_id: booking.room_id,
              total: booking.total,
              paid,
              balance: Math.max(0, booking.total - paid),
              payout_note: ["airbnb", "booking_com", "makemytrip", "goibibo", "agoda"].includes(booking.source)
                ? "The channel adds tax you remit and may deduct TDS, so the amount it transfers can differ."
                : null,
            }
          : null,
        property_info: property
          ? [
              ["Address", property.address?.formattedAddress || [property.address?.city, property.address?.state].filter(Boolean).join(", ")],
              ["Check-in time", property.checkInTime],
              ["Check-out time", property.checkOutTime],
              ["Check-in method", METHOD_LABELS[property.checkInMethod] ?? property.checkInMethod],
              ["Caretaker", [property.caretaker?.name, property.caretaker?.phone].filter(Boolean).join(" · ")],
              ["House rules", property.houseRules?.additionalRules],
              ["Max guests", property.capacity?.guests ? String(property.capacity.guests) : ""],
              ["Cancellation policy", property.cancellationPolicy],
              ["Description", property.description],
            ]
              .filter(([, v]) => v)
              .map(([label, value]) => ({ label, value }))
          : [],
      });
    }),
  );

  function validBody(body) {
    const text = String(body ?? "").trim();
    if (!text) throw new InputError("Write a message first");
    if (text.length > MAX_BODY) throw new InputError(`Keep messages under ${MAX_BODY} characters`);
    return text;
  }

  // Reply (out) or log what the guest sent (in). Variables are filled in.
  router.post(
    "/:id/messages",
    handle(async (req, res) => {
      const t = await scoped(req);
      const direction = req.body?.direction === "in" ? "in" : "out";
      const { booking, property } = await context(t);
      let text = validBody(req.body?.body);
      if (direction === "out") text = await fillTemplate(db, text, { thread: t, booking, property, req });
      const at = nowIso();
      const msg = { id: `${t.id}-${t.messages.length + 1}-${Date.now()}`, direction, body: text, at, by: direction === "out" ? byName(req) : t.guest_name, by_id: req.user.id, logged_by: direction === "in" ? byName(req) : undefined, delivery: direction === "out" ? "recorded" : undefined };
      // Replying marks the conversation read; a logged guest message stays unread until someone replies or opens it.
      const user_state = direction === "out" ? { ...t.user_state, [req.user.id]: { ...stateFor(t, req.user.id), read_at: at } } : t.user_state;
      const updated = await db.updateDoc("threads", { id: t.id }, { messages: [...t.messages, msg], last_message_at: at, user_state });
      return res.status(201).json({ message: msg, total: updated.messages.length });
    }),
  );

  // Preview a template for this conversation (quick replies "Put in reply").
  router.post("/:id/render", handle(async (req, res) => {
    const t = await scoped(req);
    const { booking, property } = await context(t);
    return res.json({ body: await fillTemplate(db, String(req.body?.body ?? ""), { thread: t, booking, property, req }) });
  }));

  // Per-user flags.
  router.post(
    "/:id/state",
    handle(async (req, res) => {
      const t = await scoped(req);
      const st = { ...stateFor(t, req.user.id) };
      for (const k of ["starred", "priority", "archived"]) if (typeof req.body?.[k] === "boolean") st[k] = req.body[k];
      if (req.body?.read === true) st.read_at = nowIso();
      if (req.body?.read === false) st.read_at = null;
      await db.updateDoc("threads", { id: t.id }, { user_state: { ...t.user_state, [req.user.id]: st } });
      return res.json({ ...st, unread: unread({ ...t, user_state: { [req.user.id]: st } }, req.user.id) });
    }),
  );

  // Team note: never sent to the guest.
  router.put(
    "/:id/note",
    handle(async (req, res) => {
      const t = await scoped(req);
      const text = String(req.body?.text ?? "").trim().slice(0, 2000);
      const note = text ? { text, edited_by: byName(req), edited_at: nowIso() } : null;
      await db.updateDoc("threads", { id: t.id }, { note });
      return res.json({ note });
    }),
  );

  // Send later (IST date/time from the client as an ISO instant).
  router.post(
    "/:id/scheduled",
    handle(async (req, res) => {
      const t = await scoped(req);
      const sendAt = new Date(String(req.body?.send_at ?? ""));
      if (Number.isNaN(sendAt.getTime()) || sendAt.getTime() < Date.now() + 60_000) throw new InputError("Pick a time at least a minute from now");
      const { booking, property } = await context(t);
      const text = await fillTemplate(db, validBody(req.body?.body), { thread: t, booking, property, req });
      const saved = await db.insertDoc("scheduled_messages", {
        org_id: t.org_id,
        thread_id: t.id,
        body: text,
        send_at: sendAt.toISOString(),
        status: "scheduled",
        booking_key: bookingKey(booking),
        by_id: req.user.id,
        by_name: byName(req),
        created_at: nowIso(),
      });
      return res.status(201).json(saved);
    }),
  );

  async function scopedScheduled(req) {
    const s = await db.findDoc("scheduled_messages", { id: Number(req.params.sid) });
    if (!s || s.org_id !== req.scope.org_id || s.thread_id !== Number(req.params.id)) throw new InputError("Scheduled message not found", 404);
    if (!["scheduled", "held"].includes(s.status)) throw new InputError("This message has already been sent or cancelled");
    return s;
  }

  router.patch(
    "/:id/scheduled/:sid",
    handle(async (req, res) => {
      const s = await scopedScheduled(req);
      const set = {};
      if (req.body?.body !== undefined) set.body = validBody(req.body.body);
      if (req.body?.send_at !== undefined) {
        const d = new Date(String(req.body.send_at));
        if (Number.isNaN(d.getTime()) || d.getTime() < Date.now() + 60_000) throw new InputError("Pick a time at least a minute from now");
        set.send_at = d.toISOString();
      }
      // Re-saving a held message confirms it for the booking as it is now.
      const t = await db.findDoc("threads", { id: s.thread_id });
      const booking = t?.booking_id ? await db.findDoc("bookings", { id: t.booking_id }) : null;
      Object.assign(set, { status: "scheduled", booking_key: bookingKey(booking), held_reason: null });
      return res.json(await db.updateDoc("scheduled_messages", { id: s.id }, set));
    }),
  );

  router.post(
    "/:id/scheduled/:sid/send-now",
    handle(async (req, res) => {
      const s = await scopedScheduled(req);
      const t = await db.findDoc("threads", { id: s.thread_id });
      const booking = t?.booking_id ? await db.findDoc("bookings", { id: t.booking_id }) : null;
      await db.updateDoc("scheduled_messages", { id: s.id }, { send_at: nowIso(), booking_key: bookingKey(booking), status: "scheduled" });
      await dispatchScheduled(db, nowIso());
      return res.json(await db.findDoc("scheduled_messages", { id: s.id }));
    }),
  );

  router.delete(
    "/:id/scheduled/:sid",
    handle(async (req, res) => {
      const s = await scopedScheduled(req);
      await db.updateDoc("scheduled_messages", { id: s.id }, { status: "cancelled" });
      return res.json({ cancelled: true });
    }),
  );

  return router;
}
