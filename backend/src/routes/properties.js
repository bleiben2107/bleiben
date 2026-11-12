import crypto from "node:crypto";
import { Router } from "express";

import { config } from "../config.js";
import { can } from "../roles.js";
import { savePhoto } from "../uploads.js";

const nowIso = () => new Date().toISOString();

function generateSerialId() {
  const code = crypto.randomBytes(3).toString("hex").toUpperCase();
  return `HH-P-${code}`;
}

class InputError extends Error {}

/**
 * Editable property fields: canonical (stored) name → accepted input names.
 * Anything not listed here (id, org_id, user_id, status, slug, serial id,
 * timestamps) can never be set through a create/update payload — status only
 * changes through /publish and DELETE.
 */
const FIELDS = {
  setupMethod: ["setupMethod", "setup_method"],
  airbnbUrl: ["airbnbUrl", "airbnb_url"],
  current_step: ["current_step", "currentStep", "propertyCurrentStep"],
  step_number: ["step_number", "stepNumber"],
  propertyType: ["propertyType", "property_type"],
  accommodationType: ["accommodationType", "accommodation_type"],
  ownershipType: ["ownershipType", "ownership_type"],
  address: ["address"],
  location: ["location"],
  photos: ["photos"],
  coverPhoto: ["coverPhoto", "cover_photo"],
  documents: ["documents"],
  amenities: ["amenities"],
  uniqueness: ["uniqueness"],
  experiences: ["experiences"],
  title: ["title"],
  description: ["description"],
  notes: ["notes"],
  videoUrl: ["videoUrl", "video_url"],
  neighbourhood: ["neighbourhood"],
  basePrice: ["basePrice", "base_price", "price"],
  extraGuestCharge: ["extraGuestCharge", "extra_guest_charge"],
  advancePercent: ["advancePercent", "advance_percent"],
  checkInTime: ["checkInTime", "check_in", "checkIn"],
  checkOutTime: ["checkOutTime", "check_out", "checkOut"],
  houseRules: ["houseRules", "house_rules"],
  instantBooking: ["instantBooking", "instant_booking"],
  cancellationPolicy: ["cancellationPolicy", "cancellation_policy"],
  checkInMethod: ["checkInMethod", "check_in_method"],
  accountVerificationStatus: ["accountVerificationStatus", "account_verification_status"],
};
const CAPACITY_KEYS = ["guests", "bedrooms", "beds", "bathrooms"];

const pick = (body, names) => {
  for (const n of names) if (body[n] !== undefined) return { found: true, value: body[n] };
  return { found: false };
};

function number(value, label, { min = 0, max = Number.MAX_SAFE_INTEGER, integer = false } = {}) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < min || n > max || (integer && !Number.isInteger(n))) {
    throw new InputError(`${label} must be ${integer ? "a whole number" : "a number"} between ${min} and ${max}`);
  }
  return n;
}

/** Validated canonical updates from a create/update payload (snake or camel case). */
function normalizeInput(body = {}) {
  const out = {};
  for (const [key, names] of Object.entries(FIELDS)) {
    const { found, value } = pick(body, names);
    if (found) out[key] = value;
  }

  // Capacity arrives either nested or as flat counters.
  const flat = Object.fromEntries(CAPACITY_KEYS.filter((k) => body[k] !== undefined).map((k) => [k, body[k]]));
  if (body.capacity || Object.keys(flat).length) {
    const capacity = { ...(body.capacity || {}), ...flat };
    out.capacity = {};
    for (const k of CAPACITY_KEYS) {
      if (capacity[k] !== undefined) out.capacity[k] = number(capacity[k], k, { min: 0, max: 500, integer: true });
    }
  }

  // Caretaker arrives nested or flat.
  const ctName = body.caretaker?.name ?? body.caretaker_name ?? body.caretakerName;
  const ctPhone = body.caretaker?.phone ?? body.caretaker_phone ?? body.caretakerPhone;
  if (ctName !== undefined || ctPhone !== undefined) {
    out.caretaker = { name: String(ctName ?? "").slice(0, 80), phone: String(ctPhone ?? "").slice(0, 20) };
  }

  if (out.title !== undefined) {
    out.title = String(out.title ?? "").trim();
    if (out.title.length > 100) throw new InputError("Title can be 100 characters at most");
  }
  for (const k of ["description", "neighbourhood"]) {
    if (out[k] !== undefined && String(out[k] ?? "").length > 10000) {
      throw new InputError(`${k[0].toUpperCase()}${k.slice(1)} can be 10,000 characters at most`);
    }
  }
  if (out.basePrice !== undefined) out.basePrice = number(out.basePrice, "Base price", { max: 10_000_000 });
  if (out.extraGuestCharge !== undefined) out.extraGuestCharge = number(out.extraGuestCharge, "Extra guest charge", { max: 1_000_000 });
  if (out.advancePercent !== undefined) out.advancePercent = number(out.advancePercent, "Advance", { min: 0, max: 100 });
  for (const k of ["photos", "documents", "amenities", "uniqueness", "experiences"]) {
    if (out[k] !== undefined && !Array.isArray(out[k])) throw new InputError(`${k} must be a list`);
  }
  if (out.address?.formattedAddress) out.location = out.address.formattedAddress;
  return out;
}

/**
 * API shape: canonical fields plus the snake_case names the Flutter client
 * reads. Older records that stored raw snake_case keys are read as fallbacks.
 */
function publicProperty(p, extra = {}) {
  const v = (camel, snake, fallback) => p[camel] ?? p[snake] ?? fallback;
  const capacity = {
    guests: p.capacity?.guests ?? p.guests ?? 1,
    bedrooms: p.capacity?.bedrooms ?? p.bedrooms ?? 1,
    beds: p.capacity?.beds ?? p.beds ?? 1,
    bathrooms: p.capacity?.bathrooms ?? p.bathrooms ?? 1,
  };
  const caretaker = {
    name: p.caretaker?.name ?? p.caretakerName ?? p.caretaker_name ?? "",
    phone: p.caretaker?.phone ?? p.caretakerPhone ?? p.caretaker_phone ?? "",
  };
  const out = {
    id: p.id,
    org_id: p.org_id ?? null,
    propertySerialId: v("propertySerialId", "property_serial_id", ""),
    status: p.status ?? "draft",
    slug: p.slug ?? null,
    booking_url: p.slug ? `${config.appBaseUrl}/p/${p.slug}` : null,
    setupMethod: v("setupMethod", "setup_method", "manual"),
    airbnbUrl: v("airbnbUrl", "airbnb_url", null),
    current_step: p.current_step ?? "property_type",
    step_number: p.step_number ?? 1,
    propertyType: v("propertyType", "property_type", "House"),
    accommodationType: v("accommodationType", "accommodation_type", "entireHouse"),
    ownershipType: v("ownershipType", "ownership_type", "owner"),
    address: p.address ?? {},
    location: p.location ?? p.address?.formattedAddress ?? "",
    city: p.address?.city ?? "",
    photos: p.photos ?? [],
    coverPhoto: v("coverPhoto", "cover_photo", null),
    documents: p.documents ?? [],
    capacity,
    amenities: p.amenities ?? [],
    uniqueness: p.uniqueness ?? [],
    experiences: p.experiences ?? [],
    title: p.title ?? "",
    description: p.description ?? "",
    notes: p.notes ?? "",
    videoUrl: v("videoUrl", "video_url", ""),
    neighbourhood: p.neighbourhood ?? "",
    basePrice: Number(v("basePrice", "base_price", 0)),
    extraGuestCharge: Number(v("extraGuestCharge", "extra_guest_charge", 0)),
    advancePercent: Number(v("advancePercent", "advance_percent", 0)),
    currency: p.currency ?? "INR",
    checkInTime: v("checkInTime", "check_in", ""),
    checkOutTime: v("checkOutTime", "check_out", ""),
    houseRules: v("houseRules", "house_rules", {}),
    instantBooking: v("instantBooking", "instant_booking", true),
    cancellationPolicy: v("cancellationPolicy", "cancellation_policy", "flexible"),
    checkInMethod: v("checkInMethod", "check_in_method", "host_greets"),
    caretaker,
    accountVerificationStatus: v("accountVerificationStatus", "account_verification_status", "pending"),
    published_at: p.published_at ?? null,
    created_at: p.created_at,
    updated_at: p.updated_at,
    ...extra,
  };
  // snake_case aliases for the Flutter Stay model
  Object.assign(out, {
    property_serial_id: out.propertySerialId,
    setup_method: out.setupMethod,
    airbnb_url: out.airbnbUrl,
    property_type: out.propertyType,
    accommodation_type: out.accommodationType,
    ownership_type: out.ownershipType,
    cover_photo: out.coverPhoto,
    ...capacity,
    video_url: out.videoUrl,
    base_price: out.basePrice,
    extra_guest_charge: out.extraGuestCharge,
    advance_percent: out.advancePercent,
    check_in: out.checkInTime,
    check_out: out.checkOutTime,
    house_rules: out.houseRules,
    instant_booking: out.instantBooking,
    cancellation_policy: out.cancellationPolicy,
    check_in_method: out.checkInMethod,
    caretaker_name: caretaker.name,
    caretaker_phone: caretaker.phone,
    account_verification_status: out.accountVerificationStatus,
  });
  return out;
}

const DEFAULTS = {
  setupMethod: "manual",
  airbnbUrl: null,
  current_step: "property_type",
  step_number: 1,
  propertyType: "House",
  accommodationType: "entireHouse",
  ownershipType: "owner",
  address: { formattedAddress: "", streetName: "", aptSuite: "", landmark: "", city: "", state: "", postalCode: "", country: "India" },
  location: "",
  photos: [],
  coverPhoto: null,
  documents: [],
  capacity: { guests: 1, bedrooms: 1, beds: 1, bathrooms: 1 },
  amenities: [],
  uniqueness: [],
  experiences: [],
  title: "",
  description: "",
  videoUrl: "",
  neighbourhood: "",
  basePrice: 0,
  extraGuestCharge: 0,
  advancePercent: 0,
  currency: "INR",
  checkInTime: "",
  checkOutTime: "",
  houseRules: { childFriendly: true, infantFriendly: true, petsAllowed: false, smokingAllowed: false, partiesAllowed: false, additionalRules: "" },
  instantBooking: true,
  cancellationPolicy: "flexible",
  checkInMethod: "host_greets",
  caretaker: { name: "", phone: "" },
  accountVerificationStatus: "pending",
};

export function slugify(text) {
  return String(text || "")
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[^\w\s-]/g, "")
    .trim()
    .replace(/[\s_]+/g, "-")
    .replace(/-+/g, "-")
    .slice(0, 40)
    .replace(/^-|-$/g, "");
}

// ── Rooms & units (MVP plan §3) ──────────────────────────────────────────────

const ROOM_TYPES = ["entire_place", "room", "suite", "dorm_bed", "tent", "cottage", "villa"];

function normalizeRoom(body = {}, { partial = false } = {}) {
  const out = {};
  const name = body.name !== undefined ? String(body.name).trim() : undefined;
  if (name !== undefined || !partial) {
    if (!name) throw new InputError("Room name is required");
    if (name.length > 60) throw new InputError("Room name can be 60 characters at most");
    out.name = name;
  }
  const type = body.room_type ?? body.roomType;
  if (type !== undefined || !partial) {
    const t = type ?? "room";
    if (!ROOM_TYPES.includes(t)) throw new InputError(`Room type must be one of: ${ROOM_TYPES.join(", ")}`);
    out.roomType = t;
  }
  const maxAdults = body.max_adults ?? body.maxAdults;
  if (maxAdults !== undefined || !partial) out.maxAdults = number(maxAdults ?? 2, "Adults", { min: 1, max: 50, integer: true });
  const maxChildren = body.max_children ?? body.maxChildren;
  if (maxChildren !== undefined || !partial) out.maxChildren = number(maxChildren ?? 0, "Children", { min: 0, max: 50, integer: true });
  const units = body.unit_count ?? body.unitCount;
  if (units !== undefined || !partial) out.unitCount = number(units ?? 1, "Number of units", { min: 1, max: 500, integer: true });
  const price = body.base_price ?? body.basePrice;
  if (price !== undefined) out.basePrice = price === null ? null : number(price, "Room price", { max: 10_000_000 });
  else if (!partial) out.basePrice = null;
  const extra = body.extra_guest_charge ?? body.extraGuestCharge;
  if (extra !== undefined) out.extraGuestCharge = extra === null ? null : number(extra, "Extra guest charge", { max: 1_000_000 });
  else if (!partial) out.extraGuestCharge = null;
  for (const k of ["amenities", "photos"]) {
    if (body[k] !== undefined) {
      if (!Array.isArray(body[k])) throw new InputError(`${k} must be a list`);
      out[k] = body[k].map(String).slice(0, 100);
    } else if (!partial) out[k] = [];
  }
  if (body.description !== undefined) out.description = String(body.description).slice(0, 2000);
  return out;
}

function publicRoom(r, property) {
  const basePrice = r.basePrice ?? null;
  const extra = r.extraGuestCharge ?? null;
  return {
    id: r.id,
    property_id: r.property_id,
    name: r.name,
    room_type: r.roomType,
    max_adults: r.maxAdults,
    max_children: r.maxChildren,
    max_guests: r.maxAdults + r.maxChildren,
    unit_count: r.unitCount,
    base_price: basePrice,
    extra_guest_charge: extra,
    // What the booking page charges: the room's own price, else the property's.
    effective_price: basePrice ?? Number(property?.basePrice ?? property?.base_price ?? 0),
    effective_extra_guest_charge: extra ?? Number(property?.extraGuestCharge ?? 0),
    amenities: r.amenities ?? [],
    photos: r.photos ?? [],
    description: r.description ?? "",
    status: r.status,
    created_at: r.created_at,
    updated_at: r.updated_at,
  };
}

export function propertiesRouter(db) {
  const router = Router();

  const handle = (fn) => async (req, res, next) => {
    try {
      return await fn(req, res);
    } catch (err) {
      if (err instanceof InputError) return res.status(400).json({ detail: err.message });
      return next(err);
    }
  };

  /** The property if it belongs to the caller's org (or, without X-Org-Id, to the caller). */
  async function findScopedProperty(id, req) {
    const numId = Number(id);
    const query = Number.isInteger(numId) ? { id: numId } : { propertySerialId: id };
    const property = await db.findDoc("properties", query);
    if (!property || property.status === "deleted") return null;
    if (req.scope.org_id != null) {
      if (property.org_id !== req.scope.org_id) return null;
    } else if (property.user_id !== req.user.id) {
      return null;
    }
    return property;
  }

  const log = (property, req, action, extra = {}) =>
    db.insertDoc("property_logs", {
      property_id: property.id,
      propertySerialId: property.propertySerialId,
      org_id: property.org_id ?? null,
      user_id: req.user.id,
      user_name: req.user.name ?? "",
      action,
      ...extra,
      timestamp: nowIso(),
    });

  async function activeRooms(propertyId) {
    return (await db.findDocs("rooms", { property_id: propertyId })).filter((r) => r.status !== "archived");
  }

  async function uniqueSlug(base, propertyId) {
    const root = slugify(base) || "stay";
    for (let i = 0; i < 50; i += 1) {
      const candidate = i === 0 ? root : `${root.slice(0, 34)}-${i + 1}`;
      const taken = await db.findDoc("properties", { slug: candidate });
      if (!taken || taken.id === propertyId) return candidate;
    }
    return `${root.slice(0, 30)}-${crypto.randomBytes(3).toString("hex")}`;
  }

  // 1. List — search by name / serial id / city, filter by status (All Properties).
  router.get(
    "/",
    handle(async (req, res) => {
      const filter = req.scope.org_id != null ? { org_id: req.scope.org_id } : { user_id: req.user.id };
      const q = String(req.query.q ?? "").trim().toLowerCase();
      const status = String(req.query.status ?? "").trim();
      const list = (await db.findDocs("properties", filter))
        .filter((p) => p.status !== "deleted")
        .filter((p) => !status || status === "all" || p.status === status)
        .filter((p) => {
          if (!q) return true;
          const hay = [p.title, p.propertySerialId, p.address?.city, p.location, String(p.id)].join(" ").toLowerCase();
          return hay.includes(q);
        })
        .sort((a, b) => (a.updated_at < b.updated_at ? 1 : -1));
      const out = [];
      for (const p of list) {
        const rooms = await activeRooms(p.id);
        out.push(publicProperty(p, { room_count: rooms.length, unit_count: rooms.reduce((n, r) => n + r.unitCount, 0) }));
      }
      return res.json(out);
    }),
  );

  // 2. Create a draft (first wizard step). Status always starts as draft.
  router.post(
    "/",
    handle(async (req, res) => {
      const input = normalizeInput(req.body);
      const now = nowIso();
      const saved = await db.insertDoc("properties", {
        ...structuredClone(DEFAULTS),
        ...input,
        capacity: { ...DEFAULTS.capacity, ...(input.capacity || {}) },
        propertySerialId: generateSerialId(),
        user_id: req.user.id,
        org_id: req.scope.org_id ?? null,
        status: "draft",
        created_at: now,
        updated_at: now,
      });
      await log(saved, req, "created_draft");
      return res.status(201).json(publicProperty(saved));
    }),
  );

  // 3. One property (with its rooms).
  router.get(
    "/:id",
    handle(async (req, res) => {
      const property = await findScopedProperty(req.params.id, req);
      if (!property) return res.status(404).json({ detail: "Property not found" });
      const rooms = await activeRooms(property.id);
      return res.json(publicProperty(property, { rooms: rooms.map((r) => publicRoom(r, property)) }));
    }),
  );

  // 4. Update any editable field (wizard step save / edit listing).
  const update = handle(async (req, res) => {
    const property = await findScopedProperty(req.params.id, req);
    if (!property) return res.status(404).json({ detail: "Property not found" });
    const updates = normalizeInput(req.body);
    if (updates.capacity) updates.capacity = { ...(property.capacity || DEFAULTS.capacity), ...updates.capacity };
    // The address is locked once the property is live (homyhuts does the same).
    if (property.status === "activated") {
      delete updates.address;
      delete updates.location;
    }
    updates.updated_at = nowIso();
    const updated = await db.updateDoc("properties", { id: property.id }, updates);
    await log(property, req, "updated", { current_step: updated.current_step, fields: Object.keys(updates).filter((k) => k !== "updated_at") });
    return res.json(publicProperty(updated));
  });
  router.put("/:id", update);
  router.patch("/:id", update);

  // 5. Photo upload (base64 JPG/PNG/WebP).
  router.post(
    "/:id/photos",
    handle(async (req, res) => {
      const property = await findScopedProperty(req.params.id, req);
      if (!property) return res.status(404).json({ detail: "Property not found" });
      const result = await savePhoto(`properties/${property.id}`, req.body);
      if (result.error) return res.status(400).json({ detail: result.error });
      const photos = [...(property.photos || []), result.url];
      const updates = { photos, updated_at: nowIso() };
      if (!property.coverPhoto) updates.coverPhoto = result.url;
      const updated = await db.updateDoc("properties", { id: property.id }, updates);
      return res.json({ url: result.url, photos: updated.photos, coverPhoto: updated.coverPhoto });
    }),
  );

  // 6. Publish: validates, makes sure there is sellable inventory, assigns the booking-page slug.
  router.post(
    "/:id/publish",
    handle(async (req, res) => {
      const property = await findScopedProperty(req.params.id, req);
      if (!property) return res.status(404).json({ detail: "Property not found" });
      if (req.membership && !can(req.membership.role, "properties.publish")) {
        return res.status(403).json({ detail: "Your role cannot publish properties" });
      }
      const p = publicProperty(property);
      if (!p.title.trim()) return res.status(400).json({ detail: "Property title is required to publish" });
      if (!p.propertyType) return res.status(400).json({ detail: "Property type is required to publish" });

      let rooms = await activeRooms(property.id);
      if (!rooms.length) {
        if (!(p.basePrice > 0)) {
          return res.status(400).json({ detail: "Set a nightly price (or add a room with a price) before publishing" });
        }
        // Entire-place listings sell as one unit.
        const now = nowIso();
        rooms = [
          await db.insertDoc("rooms", {
            property_id: property.id,
            org_id: property.org_id ?? null,
            name: "Entire property",
            roomType: "entire_place",
            maxAdults: Math.max(1, p.capacity.guests),
            maxChildren: 0,
            unitCount: 1,
            basePrice: null,
            extraGuestCharge: null,
            amenities: [],
            photos: [],
            status: "active",
            created_at: now,
            updated_at: now,
          }),
        ];
      } else if (!rooms.some((r) => (r.basePrice ?? p.basePrice) > 0)) {
        return res.status(400).json({ detail: "Set a nightly price on the property or its rooms before publishing" });
      }

      const now = nowIso();
      const slug = property.slug || (await uniqueSlug(p.title, property.id));
      const activated = await db.updateDoc(
        "properties",
        { id: property.id },
        { status: "activated", slug, current_step: "publish_property", published_at: property.published_at ?? now, updated_at: now },
      );
      await log(property, req, "published", { slug });
      return res.json({ ok: true, property: publicProperty(activated, { rooms: rooms.map((r) => publicRoom(r, activated)) }) });
    }),
  );

  // Take a live property off the booking page (back to draft, keeps its slug).
  router.post(
    "/:id/unpublish",
    handle(async (req, res) => {
      const property = await findScopedProperty(req.params.id, req);
      if (!property) return res.status(404).json({ detail: "Property not found" });
      if (req.membership && !can(req.membership.role, "properties.publish")) {
        return res.status(403).json({ detail: "Your role cannot unpublish properties" });
      }
      const updated = await db.updateDoc("properties", { id: property.id }, { status: "deactivated", updated_at: nowIso() });
      await log(property, req, "unpublished");
      return res.json(publicProperty(updated));
    }),
  );

  // 7. Archive (soft delete).
  router.delete(
    "/:id",
    handle(async (req, res) => {
      const property = await findScopedProperty(req.params.id, req);
      if (!property) return res.status(404).json({ detail: "Property not found" });
      if (req.membership && !can(req.membership.role, "properties.delete")) {
        return res.status(403).json({ detail: "Your role cannot delete properties" });
      }
      await db.updateDoc("properties", { id: property.id }, { status: "deleted", deleted_at: nowIso(), updated_at: nowIso() });
      await log(property, req, "deleted");
      return res.status(204).end();
    }),
  );

  // 8. Clone an existing property (and its rooms) into a new draft.
  router.post(
    "/clone/:id",
    handle(async (req, res) => {
      const property = await findScopedProperty(req.params.id, req);
      if (!property) return res.status(404).json({ detail: "Original property not found" });
      const now = nowIso();
      const copy = structuredClone(property);
      for (const k of ["id", "slug", "published_at", "deleted_at"]) delete copy[k];
      const cloned = await db.insertDoc("properties", {
        ...copy,
        propertySerialId: generateSerialId(),
        title: String(req.query.title || `${property.title} (Copy)`).slice(0, 100),
        status: "draft",
        current_step: "property_type",
        user_id: req.user.id,
        created_at: now,
        updated_at: now,
      });
      for (const r of await activeRooms(property.id)) {
        const { id: _id, ...room } = r;
        await db.insertDoc("rooms", { ...room, property_id: cloned.id, created_at: now, updated_at: now });
      }
      await log(cloned, req, "cloned", { from: property.propertySerialId });
      return res.status(201).json(publicProperty(cloned));
    }),
  );

  // Activity log (property detail → Activity tab).
  router.get(
    "/:id/activity",
    handle(async (req, res) => {
      const property = await findScopedProperty(req.params.id, req);
      if (!property) return res.status(404).json({ detail: "Property not found" });
      const logs = (await db.findDocs("property_logs", { property_id: property.id }))
        .sort((a, b) => (a.timestamp < b.timestamp ? 1 : -1))
        .slice(0, 200)
        .map((l) => ({ id: l.id, action: l.action, user_name: l.user_name ?? "", fields: l.fields ?? [], current_step: l.current_step ?? null, slug: l.slug ?? null, at: l.timestamp }));
      return res.json(logs);
    }),
  );

  // ── Rooms & units ─────────────────────────────────────────────────────────

  router.get(
    "/:id/rooms",
    handle(async (req, res) => {
      const property = await findScopedProperty(req.params.id, req);
      if (!property) return res.status(404).json({ detail: "Property not found" });
      const includeArchived = req.query.include_archived === "1";
      const rooms = (await db.findDocs("rooms", { property_id: property.id }))
        .filter((r) => includeArchived || r.status !== "archived")
        .sort((a, b) => a.id - b.id);
      return res.json(rooms.map((r) => publicRoom(r, property)));
    }),
  );

  router.post(
    "/:id/rooms",
    handle(async (req, res) => {
      const property = await findScopedProperty(req.params.id, req);
      if (!property) return res.status(404).json({ detail: "Property not found" });
      const input = normalizeRoom(req.body);
      if ((await activeRooms(property.id)).some((r) => r.name.toLowerCase() === input.name.toLowerCase())) {
        return res.status(409).json({ detail: `A room called "${input.name}" already exists` });
      }
      const now = nowIso();
      const room = await db.insertDoc("rooms", {
        ...input,
        property_id: property.id,
        org_id: property.org_id ?? null,
        status: "active",
        created_at: now,
        updated_at: now,
      });
      await log(property, req, "room_added", { fields: [room.name] });
      return res.status(201).json(publicRoom(room, property));
    }),
  );

  router.patch(
    "/:id/rooms/:roomId",
    handle(async (req, res) => {
      const property = await findScopedProperty(req.params.id, req);
      if (!property) return res.status(404).json({ detail: "Property not found" });
      const room = await db.findDoc("rooms", { id: Number(req.params.roomId), property_id: property.id });
      if (!room) return res.status(404).json({ detail: "Room not found" });
      const input = normalizeRoom(req.body, { partial: true });
      if (input.name && input.name.toLowerCase() !== room.name.toLowerCase()) {
        if ((await activeRooms(property.id)).some((r) => r.id !== room.id && r.name.toLowerCase() === input.name.toLowerCase())) {
          return res.status(409).json({ detail: `A room called "${input.name}" already exists` });
        }
      }
      if (req.body?.status !== undefined) {
        if (!["active", "archived"].includes(req.body.status)) return res.status(400).json({ detail: "Status must be active or archived" });
        input.status = req.body.status;
      }
      const updated = await db.updateDoc("rooms", { id: room.id }, { ...input, updated_at: nowIso() });
      await log(property, req, "room_updated", { fields: [updated.name] });
      return res.json(publicRoom(updated, property));
    }),
  );

  // Archive a room (kept for booking history; MVP plan: "add/edit/archive rooms").
  router.delete(
    "/:id/rooms/:roomId",
    handle(async (req, res) => {
      const property = await findScopedProperty(req.params.id, req);
      if (!property) return res.status(404).json({ detail: "Property not found" });
      const room = await db.findDoc("rooms", { id: Number(req.params.roomId), property_id: property.id });
      if (!room) return res.status(404).json({ detail: "Room not found" });
      if (property.status === "activated" && (await activeRooms(property.id)).length === 1) {
        return res.status(409).json({ detail: "A live property needs at least one room. Unpublish it first or add another room." });
      }
      await db.updateDoc("rooms", { id: room.id }, { status: "archived", updated_at: nowIso() });
      await log(property, req, "room_archived", { fields: [room.name] });
      return res.status(204).end();
    }),
  );

  return router;
}
