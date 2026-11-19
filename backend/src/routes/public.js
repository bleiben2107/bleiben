import crypto from "node:crypto";

import { Router } from "express";

import {
  InputError,
  assertAvailable,
  bookingCode,
  nowIso,
  quote,
  requireRange,
  roomBasePrice,
  withLocks,
} from "../bookings/core.js";
import { notify } from "../notify.js";
import { createOrder, orgGateway, verifyPayment, verifyWebhook } from "../payments/gateway.js";
import { hashSecret, secretsMatch } from "../tokens.js";
import { entitlement } from "../billing/subscription.js";

/**
 * Public direct-booking page (MVP plan §6 core promise):
 * guest selects dates → enters details → Bleiben holds the room for 15
 * minutes → the payment is verified → the reservation is confirmed and
 * appears in the owner's calendar, with notifications to both sides.
 * Without an online gateway the guest sends a booking request (inquiry).
 */

const HOLD_MINUTES = 15;
const PHONE_RE = /^\+?[0-9 ()-]{7,20}$/;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$/;

const handle = (fn) => async (req, res, next) => {
  try {
    return await fn(req, res);
  } catch (err) {
    if (err instanceof InputError) return res.status(err.status).json({ detail: err.message, ...err.extra });
    return next(err);
  }
};

/** Small in-memory limiter: N requests per window per IP and key. */
function limiter(max, windowMs) {
  const hits = new Map();
  return (req, key) => {
    const k = `${req.ip}:${key}`;
    const now = Date.now();
    const list = (hits.get(k) ?? []).filter((t) => now - t < windowMs);
    if (list.length >= max) throw new InputError("Too many attempts. Please wait a few minutes and try again.", 429);
    list.push(now);
    hits.set(k, list);
  };
}

async function liveProperty(db, slug) {
  const p = await db.findDoc("properties", { slug: String(slug) });
  if (!p || p.status !== "activated") throw new InputError("This stay isn't available for booking", 404);
  return p;
}

async function activeRooms(db, propertyId) {
  return (await db.findDocs("rooms", { property_id: propertyId })).filter((r) => r.status !== "archived");
}

function publicStay(p, rooms, gateway, open) {
  return {
    slug: p.slug,
    title: p.title,
    description: p.description ?? "",
    property_type: p.propertyType,
    city: p.address?.city ?? "",
    state: p.address?.state ?? "",
    location: [p.address?.city, p.address?.state].filter(Boolean).join(", "),
    photos: p.photos ?? [],
    cover_photo: p.coverPhoto ?? p.photos?.[0] ?? null,
    amenities: p.amenities ?? [],
    capacity: p.capacity ?? {},
    check_in_time: p.checkInTime ?? "",
    check_out_time: p.checkOutTime ?? "",
    house_rules: p.houseRules ?? {},
    cancellation_policy: p.cancellationPolicy ?? "",
    advance_percent: Number(p.advancePercent ?? 0),
    rooms: rooms.map((r) => ({
      id: r.id,
      name: r.name,
      room_type: r.roomType,
      description: r.description ?? "",
      max_adults: r.maxAdults,
      max_children: r.maxChildren,
      max_guests: (r.maxAdults ?? 0) + (r.maxChildren ?? 0),
      price_from: roomBasePrice(r, p),
      photos: r.photos ?? [],
      amenities: r.amenities ?? [],
    })),
    booking_mode: !open ? "closed" : gateway ? "instant" : "request",
    payment_provider: gateway?.provider ?? null,
  };
}

function validateGuest(g) {
  const name = String(g?.name ?? "").trim();
  const phone = String(g?.phone ?? "").trim();
  const email = String(g?.email ?? "").trim().toLowerCase();
  if (name.length < 2) throw new InputError("Enter your full name");
  if (!PHONE_RE.test(phone)) throw new InputError("Enter a valid phone number");
  if (email && !EMAIL_RE.test(email)) throw new InputError("Enter a valid email address");
  return { name: name.slice(0, 80), phone, email };
}

function guestCounts(body, room) {
  const adults = Math.max(1, Math.floor(Number(body.adults) || 1));
  const children = Math.max(0, Math.floor(Number(body.children) || 0));
  const max = (room.maxAdults ?? 2) + (room.maxChildren ?? 0);
  if (adults + children > max) throw new InputError(`${room.name} takes up to ${max} guests`);
  return { adults, children };
}

const guestEvent = (action, detail = "") => ({ at: nowIso(), by: "Guest (booking page)", action, detail });

function guestView(b, property, room) {
  const paid = (b.payments ?? []).reduce((s, p) => s + (p.kind === "refund" ? -p.amount : p.amount), 0);
  return {
    code: b.code,
    status: b.status,
    property: property?.title ?? "",
    slug: property?.slug ?? null,
    room: room?.name ?? "",
    check_in: b.check_in,
    check_out: b.check_out,
    guest_name: b.guest?.name ?? "",
    adults: b.adults,
    children: b.children,
    total: b.total,
    paid,
    balance: Math.max(0, b.total - paid),
    amount_due_now: b.amount_due_now ?? 0,
    hold_expires_at: b.status === "held" ? b.hold_expires_at : null,
  };
}

/**
 * Marks a gateway payment successful: confirms the booking (re-checking
 * inventory if the hold lapsed), records the payment and notifies.
 * Idempotent — the checkout callback and the webhook can both arrive.
 */
export async function settleSuccess(db, services, attempt, paymentId) {
  return withLocks([`room:${attempt.room_id}`], async () => {
    const fresh = await db.findDoc("payment_attempts", { id: attempt.id });
    if (fresh.status === "paid" || fresh.status === "paid_conflict") return fresh;
    const b = await db.findDoc("bookings", { id: attempt.booking_id });
    const now = nowIso();
    let conflict = false;
    if (!["held", "pending_payment"].includes(b.status)) {
      conflict = true;
    } else if (b.status === "held" && Date.parse(b.hold_expires_at) <= Date.now()) {
      // Hold lapsed while paying: confirm only if the room is still free.
      const room = await db.findDoc("rooms", { id: b.room_id });
      const property = await db.findDoc("properties", { id: b.property_id });
      try {
        await assertAvailable(db, room, property, b.check_in, b.check_out, b.id);
      } catch {
        conflict = true;
      }
    }
    const payment = { amount: fresh.amount, method: "online", kind: "payment", reference: paymentId, note: fresh.provider, at: now, by: "Guest (online)" };
    if (conflict) {
      // Money was taken but the dates are gone: keep the record and tell the owner to refund.
      await db.updateDoc("payment_attempts", { id: fresh.id }, { status: "paid_conflict", payment_id: paymentId, updated_at: now });
      await db.updateDoc("bookings", { id: b.id }, {
        payments: [...(b.payments ?? []), payment],
        paid: (b.paid ?? 0) + fresh.amount,
        events: [...(b.events ?? []), guestEvent("payment", `₹${fresh.amount} online — dates no longer free, refund needed`)],
        updated_at: now,
      });
      await notify(db, services, { orgId: b.org_id, kind: "payment_failed", booking: b, guest: false, extra: { amount: fresh.amount, reason: "Paid after the hold expired and the dates were taken — refund the guest" } });
      return { ...fresh, status: "paid_conflict" };
    }
    const updated = await db.updateDoc("bookings", { id: b.id }, {
      status: "confirmed",
      hold_expires_at: null,
      payments: [...(b.payments ?? []), payment],
      paid: (b.paid ?? 0) + fresh.amount,
      events: [...(b.events ?? []), guestEvent("payment", `₹${fresh.amount} online · ${fresh.provider}`), guestEvent("confirmed")],
      updated_at: now,
    });
    const done = await db.updateDoc("payment_attempts", { id: fresh.id }, { status: "paid", payment_id: paymentId, updated_at: now });
    await notify(db, services, { orgId: b.org_id, kind: "booking_confirmed", booking: updated });
    await notify(db, services, { orgId: b.org_id, kind: "payment_received", booking: updated, guest: false, extra: { amount: fresh.amount, method: "Online" } });
    return done;
  });
}

export async function settleFailure(db, services, attempt, reason) {
  const fresh = await db.findDoc("payment_attempts", { id: attempt.id });
  if (fresh.status !== "created") return fresh;
  const b = await db.findDoc("bookings", { id: fresh.booking_id });
  const done = await db.updateDoc("payment_attempts", { id: fresh.id }, { status: "failed", error: String(reason ?? "").slice(0, 200), updated_at: nowIso() });
  await db.updateDoc("bookings", { id: b.id }, { events: [...(b.events ?? []), guestEvent("payment_failed", String(reason ?? "").slice(0, 120))] });
  await notify(db, services, { orgId: b.org_id, kind: "payment_failed", booking: b, extra: { amount: fresh.amount, reason } });
  return done;
}

/**
 * The gateway used for this stay's booking link. Instant booking switched off
 * on the property turns the link into booking requests (host confirms).
 */
async function stayGateway(db, p) {
  if (p.instantBooking === false || p.instant_booking === false) return null;
  return orgGateway(db, p.org_id);
}

export function publicRouter(db, services = {}) {
  const router = Router();
  const bookLimit = limiter(10, 60 * 60 * 1000);
  const payLimit = limiter(30, 60 * 60 * 1000);
  const fetchImpl = services.fetch ?? fetch;

  router.get(
    "/stays/:slug",
    handle(async (req, res) => {
      const p = await liveProperty(db, req.params.slug);
      const rooms = await activeRooms(db, p.id);
      const ent = await entitlement(db, p.org_id);
      return res.json(publicStay(p, rooms, await stayGateway(db, p), ent.bookable));
    }),
  );

  // Live availability + price for each room.
  router.post(
    "/stays/:slug/quote",
    handle(async (req, res) => {
      const p = await liveProperty(db, req.params.slug);
      const { check_in: checkIn, check_out: checkOut } = req.body ?? {};
      requireRange(checkIn, checkOut);
      if (checkIn < new Date().toISOString().slice(0, 10)) throw new InputError("Pick dates from today onwards");
      const guests = (Number(req.body?.adults) || 1) + (Number(req.body?.children) || 0);
      const out = [];
      for (const r of await activeRooms(db, p.id)) {
        try {
          const snap = await assertAvailable(db, r, p, checkIn, checkOut);
          const q = quote(r, p, snap, guests);
          const fits = guests <= (r.maxAdults ?? 2) + (r.maxChildren ?? 0);
          out.push({ room_id: r.id, available: fits, reason: fits ? null : "Too many guests for this room", ...q });
        } catch (err) {
          if (!(err instanceof InputError)) throw err;
          out.push({ room_id: r.id, available: false, reason: "Not available for these dates" });
        }
      }
      return res.json({ check_in: checkIn, check_out: checkOut, rooms: out, advance_percent: Number(p.advancePercent ?? 0) });
    }),
  );

  // Book: hold + payment order (instant) or a booking request (no gateway).
  router.post(
    "/stays/:slug/book",
    handle(async (req, res) => {
      bookLimit(req, "book");
      const p = await liveProperty(db, req.params.slug);
      const ent = await entitlement(db, p.org_id);
      if (!ent.bookable) throw new InputError("This stay isn't taking online bookings right now. Please contact the host.", 403);
      const body = req.body ?? {};
      requireRange(body.check_in, body.check_out);
      if (body.check_in < new Date().toISOString().slice(0, 10)) throw new InputError("Pick dates from today onwards");
      const room = (await activeRooms(db, p.id)).find((r) => r.id === Number(body.room_id));
      if (!room) throw new InputError("Choose a room", 404);
      const guest = validateGuest(body.guest);
      const { adults, children } = guestCounts(body, room);
      const gw = await stayGateway(db, p);
      const token = crypto.randomBytes(24).toString("base64url");
      const now = nowIso();

      const booking = await withLocks([`room:${room.id}`], async () => {
        const snap = await assertAvailable(db, room, p, body.check_in, body.check_out);
        const q = quote(room, p, snap, adults + children);
        const pct = Math.min(100, Math.max(0, Number(p.advancePercent ?? 0)));
        const due = gw ? (pct > 0 && pct < 100 ? Math.ceil((q.total * pct) / 100) : q.total) : 0;
        return db.insertDoc("bookings", {
          org_id: p.org_id,
          property_id: p.id,
          room_id: room.id,
          code: bookingCode(),
          status: gw ? "held" : "inquiry",
          source: "direct",
          check_in: body.check_in,
          check_out: body.check_out,
          guest,
          adults,
          children,
          quote: q,
          total: q.total,
          amount_due_now: due,
          payments: [],
          paid: 0,
          notes: String(body.notes ?? "").trim().slice(0, 500),
          hold_expires_at: gw ? new Date(Date.now() + HOLD_MINUTES * 60000).toISOString() : null,
          guest_token_hash: hashSecret(token),
          created_by: null,
          created_at: now,
          updated_at: now,
          events: [guestEvent(gw ? "held" : "inquiry", gw ? "Booking page · waiting for payment" : "Booking request from the booking page")],
        });
      });

      if (!gw) {
        await notify(db, services, { orgId: p.org_id, kind: "booking_created", booking, guest: false });
        return res.status(201).json({ booking: guestView(booking, p, room), token, payment: null });
      }
      let order;
      try {
        order = await createOrder(gw, { amount: booking.amount_due_now, receipt: booking.code, notes: { booking: booking.code } }, fetchImpl);
      } catch (err) {
        // Release the hold so the dates aren't stuck.
        await db.updateDoc("bookings", { id: booking.id }, { status: "expired", events: [...booking.events, guestEvent("expired", "Payment couldn't start")] });
        throw new InputError(`Online payment isn't available right now (${err.message}). Please try again or contact the host.`, 502);
      }
      const attempt = await db.insertDoc("payment_attempts", {
        org_id: p.org_id,
        booking_id: booking.id,
        room_id: room.id,
        provider: gw.provider,
        order_id: order.orderId,
        amount: booking.amount_due_now,
        status: "created",
        created_at: now,
        updated_at: now,
      });
      return res.status(201).json({
        booking: guestView(booking, p, room),
        token,
        payment: { attempt_id: attempt.id, provider: gw.provider, order_id: order.orderId, amount: order.amount, currency: order.currency, key_id: order.keyId ?? null },
      });
    }),
  );

  async function guestBooking(code, token) {
    const b = await db.findDoc("bookings", { code: String(code) });
    if (!b || !b.guest_token_hash || !token || !secretsMatch(String(token), b.guest_token_hash)) throw new InputError("Booking not found", 404);
    return b;
  }

  // Checkout callback: verify the payment, confirm the booking.
  router.post(
    "/payments/:attemptId/verify",
    handle(async (req, res) => {
      payLimit(req, "verify");
      const attempt = await db.findDoc("payment_attempts", { id: Number(req.params.attemptId) });
      if (!attempt) throw new InputError("Payment not found", 404);
      const b = await db.findDoc("bookings", { id: attempt.booking_id });
      await guestBooking(b.code, req.body?.token);
      const gw = await orgGateway(db, attempt.org_id);
      if (!gw || gw.provider !== attempt.provider) throw new InputError("Online payment isn't available right now", 409);
      const v = verifyPayment(gw, attempt, req.body ?? {});
      const result = v.ok ? await settleSuccess(db, services, attempt, v.paymentId) : await settleFailure(db, services, attempt, v.reason);
      const fresh = await db.findDoc("bookings", { id: b.id });
      return res.json({
        payment_status: result.status,
        message: result.status === "paid" ? "Payment received — your booking is confirmed." : result.status === "paid_conflict"
          ? "Payment received, but these dates were just taken. The host will refund you." : v.reason ?? "Payment failed",
        booking: guestView(fresh, await db.findDoc("properties", { id: fresh.property_id }), await db.findDoc("rooms", { id: fresh.room_id })),
      });
    }),
  );

  // Retry a failed payment while the hold is still active.
  router.post(
    "/bookings/:code/retry-payment",
    handle(async (req, res) => {
      payLimit(req, "retry");
      const b = await guestBooking(req.params.code, req.body?.token);
      if (b.status !== "held" || Date.parse(b.hold_expires_at) <= Date.now()) throw new InputError("This hold has expired. Please start again.", 409);
      const gw = await orgGateway(db, b.org_id);
      if (!gw) throw new InputError("Online payment isn't available right now", 409);
      const order = await createOrder(gw, { amount: b.amount_due_now, receipt: b.code, notes: { booking: b.code } }, fetchImpl);
      const now = nowIso();
      const attempt = await db.insertDoc("payment_attempts", { org_id: b.org_id, booking_id: b.id, room_id: b.room_id, provider: gw.provider, order_id: order.orderId, amount: b.amount_due_now, status: "created", created_at: now, updated_at: now });
      return res.status(201).json({ attempt_id: attempt.id, provider: gw.provider, order_id: order.orderId, amount: order.amount, currency: order.currency, key_id: order.keyId ?? null });
    }),
  );

  router.get(
    "/bookings/:code",
    handle(async (req, res) => {
      const b = await guestBooking(req.params.code, req.query.token);
      return res.json(guestView(b, await db.findDoc("properties", { id: b.property_id }), await db.findDoc("rooms", { id: b.room_id })));
    }),
  );

  // Razorpay webhook (configure https://<api>/api/public/payments/razorpay/<orgId> in the owner's dashboard).
  router.post(
    "/payments/razorpay/:orgId",
    handle(async (req, res) => {
      const orgId = Number(req.params.orgId);
      const gw = await orgGateway(db, orgId);
      const raw = Buffer.isBuffer(req.body) ? req.body.toString("utf8") : "";
      if (!verifyWebhook(gw, raw, req.headers["x-razorpay-signature"])) return res.status(400).json({ detail: "Bad signature" });
      const evt = JSON.parse(raw);
      const pay = evt?.payload?.payment?.entity;
      const orderId = pay?.order_id ?? evt?.payload?.order?.entity?.id;
      const attempt = orderId ? await db.findDoc("payment_attempts", { order_id: orderId, org_id: orgId }) : null;
      if (!attempt) return res.json({ ok: true, ignored: true });
      if (["payment.captured", "order.paid"].includes(evt.event)) await settleSuccess(db, services, attempt, pay?.id ?? "webhook");
      else if (evt.event === "payment.failed") await settleFailure(db, services, attempt, pay?.error_description ?? "Payment failed");
      return res.json({ ok: true });
    }),
  );

  return router;
}
