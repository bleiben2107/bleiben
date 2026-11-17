import { config } from "./config.js";
import { nowIso } from "./bookings/core.js";

/**
 * Notification service (MVP plan §2.6 "Basic notifications – R1").
 * Every event creates an in-app notification for the organisation (owner
 * alert) and, where the org's preferences allow, sends:
 *   - the guest an email, or an SMS when there's no email (SMS fallback);
 *   - the owner team an email alert.
 * Each delivery attempt is recorded with its status (sent / failed / skipped).
 */

export const NOTIFICATION_KINDS = {
  booking_confirmed: "Booking confirmed",
  booking_created: "New booking",
  booking_cancelled: "Booking cancelled",
  payment_received: "Payment received",
  payment_failed: "Payment failed",
  hold_expired: "Hold expired",
  sync_conflict: "Calendar conflict",
  sync_error: "Calendar sync failed",
  subscription: "Subscription",
};

/** Defaults: everything on. Orgs override in Settings → Notifications. */
export const DEFAULT_NOTIFICATION_PREFS = {
  guest_email: true,
  guest_sms: true,
  owner_email: true,
  events: Object.fromEntries(Object.keys(NOTIFICATION_KINDS).map((k) => [k, true])),
};

const SOURCE_LABEL = {
  direct: "Bleiben Direct", airbnb: "Airbnb", booking_com: "Booking.com", makemytrip: "MakeMyTrip", goibibo: "Goibibo",
  agoda: "Agoda", phone: "Phone", whatsapp: "WhatsApp", walk_in: "Walk-in", manual: "Manual",
};

const rupees = (n) => `₹${Math.round(Number(n) || 0).toLocaleString("en-IN")}`;
const pretty = (d) => {
  if (!d) return "";
  const [y, m, day] = d.split("-").map(Number);
  return `${day} ${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][m - 1]} ${y}`;
};

export async function orgPrefs(db, orgId) {
  const s = await db.findDoc("org_settings", { org_id: orgId });
  const p = s?.notifications ?? {};
  return { ...DEFAULT_NOTIFICATION_PREFS, ...p, events: { ...DEFAULT_NOTIFICATION_PREFS.events, ...(p.events ?? {}) } };
}

/** Guest-facing and owner-facing text for each booking event. */
function compose(kind, { booking, property, room, extra = {} }) {
  const guestFirst = String(booking?.guest?.name ?? "").split(" ")[0] || "there";
  const stay = booking ? `${pretty(booking.check_in)} → ${pretty(booking.check_out)}` : "";
  const place = [property?.title, room?.name].filter(Boolean).join(" · ");
  const paid = (booking?.payments ?? []).reduce((s, p) => s + (p.kind === "refund" ? -p.amount : p.amount), 0);
  const balance = Math.max(0, (booking?.total ?? 0) - paid);
  const lines = {
    booking_confirmed: {
      title: `Booking ${booking?.code} confirmed`,
      body: `${booking?.guest?.name} · ${place} · ${stay}`,
      guestSubject: `Your stay at ${property?.title} is confirmed (${booking?.code})`,
      guestText: `Hi ${guestFirst},\n\nYour booking ${booking?.code} at ${place} is confirmed for ${stay}.\nTotal ${rupees(booking?.total)} · paid ${rupees(paid)}${balance ? ` · balance ${rupees(balance)} due at the property` : ""}.\n\nCheck-in from ${property?.checkInTime || "the usual time"}, check-out by ${property?.checkOutTime || "the usual time"}.\n\nSee you soon,\n${property?.title}`,
      sms: `${property?.title}: booking ${booking?.code} confirmed for ${stay}. Paid ${rupees(paid)}${balance ? `, balance ${rupees(balance)}` : ""}.`,
    },
    booking_created: {
      title: `New booking ${booking?.code}`,
      body: `${booking?.guest?.name} · ${place} · ${stay} · ${SOURCE_LABEL[booking?.source] ?? booking?.source}`,
    },
    booking_cancelled: {
      title: `Booking ${booking?.code} cancelled`,
      body: `${booking?.guest?.name} · ${place} · ${stay}${booking?.cancel_reason ? ` · ${booking.cancel_reason}` : ""}`,
      guestSubject: `Your booking ${booking?.code} has been cancelled`,
      guestText: `Hi ${guestFirst},\n\nYour booking ${booking?.code} at ${place} for ${stay} has been cancelled.${paid > 0 ? ` Any refund due will be processed by ${property?.title}.` : ""}\n\n${property?.title}`,
      sms: `${property?.title}: booking ${booking?.code} for ${stay} has been cancelled.`,
    },
    payment_received: {
      title: `Payment ${rupees(extra.amount)} received · ${booking?.code}`,
      body: `${booking?.guest?.name} · ${extra.method ?? ""}${balance ? ` · balance ${rupees(balance)}` : " · fully paid"}`,
      guestSubject: `Payment received for ${booking?.code}`,
      guestText: `Hi ${guestFirst},\n\nWe received your payment of ${rupees(extra.amount)} for booking ${booking?.code} (${stay}).${balance ? ` Balance due: ${rupees(balance)}.` : " Your booking is fully paid."}\n\n${property?.title}`,
      sms: `${property?.title}: payment ${rupees(extra.amount)} received for ${booking?.code}.${balance ? ` Balance ${rupees(balance)}.` : ""}`,
    },
    payment_failed: {
      title: `Payment failed · ${booking?.code}`,
      body: `${booking?.guest?.name} · ${rupees(extra.amount)}${extra.reason ? ` · ${extra.reason}` : ""}`,
      guestSubject: `Payment for ${booking?.code} didn't go through`,
      guestText: `Hi ${guestFirst},\n\nYour payment of ${rupees(extra.amount)} for ${place} (${stay}) didn't go through, so the dates are not booked yet. You can try again from the booking page while the dates are free.\n\n${property?.title}`,
      sms: `${property?.title}: your payment for ${stay} didn't go through. The dates are not booked yet.`,
    },
    hold_expired: {
      title: `Hold expired · ${booking?.code}`,
      body: `${booking?.guest?.name} · ${place} · ${stay} — dates released`,
    },
  };
  return lines[kind] ?? { title: extra.title ?? NOTIFICATION_KINDS[kind] ?? kind, body: extra.body ?? "" };
}

async function ownerEmails(db, orgId) {
  const members = await db.findDocs("memberships", { org_id: orgId, status: "active" });
  const out = [];
  for (const m of members) {
    if (!["owner", "manager"].includes(m.role)) continue;
    const u = await db.findUserById(m.user_id);
    if (u?.email) out.push(u.email);
  }
  return out;
}

async function deliver(channel, to, fn) {
  if (!to) return { channel, to: null, status: "skipped", reason: "no address" };
  try {
    const r = await fn();
    // Console mailers / SMS stubs report delivered:false — record as "logged".
    return { channel, to, status: r?.delivered === false ? "logged" : "sent", at: nowIso() };
  } catch (err) {
    return { channel, to, status: "failed", error: String(err?.message ?? err).slice(0, 200), at: nowIso() };
  }
}

/**
 * Creates the notification and sends what the preferences allow.
 * Never throws: notifications must not break the booking flow.
 */
export async function notify(db, services, { orgId, kind, booking = null, extra = {}, guest = true, owner = true }) {
  try {
    const prefs = await orgPrefs(db, orgId);
    const property = booking ? await db.findDoc("properties", { id: booking.property_id }) : null;
    const room = booking ? await db.findDoc("rooms", { id: booking.room_id }) : null;
    const text = compose(kind, { booking, property, room, extra });
    const enabled = prefs.events[kind] !== false;
    const deliveries = [];
    const mailer = services?.mailer;
    const sms = services?.sms;

    if (enabled && guest && text.guestText && booking?.guest) {
      if (prefs.guest_email && booking.guest.email && mailer) {
        deliveries.push(await deliver("email", booking.guest.email, () =>
          mailer.send({ to: booking.guest.email, subject: text.guestSubject, text: text.guestText })));
      }
      const emailFailed = !booking.guest.email || deliveries.some((d) => d.channel === "email" && d.status === "failed");
      if (prefs.guest_sms && emailFailed && booking.guest.phone && sms) {
        deliveries.push(await deliver("sms", booking.guest.phone, () => sms.send({ to: booking.guest.phone, text: text.sms })));
      }
    }
    if (enabled && owner && prefs.owner_email && mailer) {
      for (const to of await ownerEmails(db, orgId)) {
        deliveries.push(await deliver("owner_email", to, () =>
          mailer.send({ to, subject: `[${config.appName}] ${text.title}`, text: `${text.title}\n${text.body}\n\nOpen the Host Control Center: ${config.appBaseUrl}` })));
      }
    }
    return await db.insertDoc("notifications", {
      org_id: orgId,
      kind,
      title: text.title,
      body: text.body,
      booking_id: booking?.id ?? null,
      booking_code: booking?.code ?? null,
      data: extra,
      deliveries,
      muted: !enabled,
      read_by: [],
      created_at: nowIso(),
    });
  } catch (err) {
    console.error("[notify]", kind, err?.message ?? err);
    return null;
  }
}
