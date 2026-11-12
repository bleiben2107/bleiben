import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { createApp } from "../src/app.js";
import { createDb } from "../src/db.js";

const PNG_1PX =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

function memoryDb(t) {
  const filePath = `./data/test-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.json`;
  t.after(() => fs.rmSync(filePath, { force: true }));
  return createDb(filePath);
}

function fakeServices() {
  const mail = [];
  const sms = [];
  return {
    mail,
    sms,
    services: {
      mailer: { configured: true, send: async (m) => (mail.push(m), { delivered: true }) },
      sms: { configured: true, send: async (m) => (sms.push(m), { delivered: true }) },
    },
  };
}

async function withServer(db, services, run) {
  const app = createApp(db, services);
  const server = app.listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  const { port } = server.address();
  const base = `http://127.0.0.1:${port}`;
  const call = async (method, path, { token, body, org } = {}) => {
    const headers = { "Content-Type": "application/json" };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (org) headers["X-Org-Id"] = String(org);
    const res = await fetch(`${base}${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
    const text = await res.text();
    let parsed = null;
    try {
      parsed = text ? JSON.parse(text) : null;
    } catch {
      parsed = text;
    }
    return { status: res.status, body: parsed, headers: res.headers };
  };
  try {
    await run(call, base);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

const codeFrom = (list) => (list.at(-1).text.match(/\d{6}/) ?? [])[0];

async function signUp(call, fakes, { name, email, phone }) {
  await call("POST", "/api/auth/signup/request-otp", {
    body: { name, email, phone, country_code: "+91" },
  });
  const ver = await call("POST", "/api/auth/signup/verify-otp", {
    body: { email, code: codeFrom(fakes.mail) },
  });
  return ver.body;
}

test("properties onboarding wizard: draft creation, step updating, photo upload, and publishing", async (t) => {
  const db = memoryDb(t);
  const fakes = fakeServices();

  await withServer(db, fakes.services, async (call) => {
    // 1. Sign up host
    const user = await signUp(call, fakes, {
      name: "Rohan Host",
      email: "rohan@example.com",
    });
    const token = user.access_token;
    const orgId = user.memberships[0].org_id;

    // 2. Create draft property (Step 0)
    const createRes = await call("POST", "/api/properties", {
      token,
      org: orgId,
      body: {
        setupMethod: "manual",
        propertyType: "Villa",
        accommodationType: "entireHouse",
      },
    });
    assert.equal(createRes.status, 201);
    assert.equal(createRes.body.status, "draft");
    assert.equal(createRes.body.propertyType, "Villa");
    assert.equal(createRes.body.accommodationType, "entireHouse");
    assert.ok(createRes.body.propertySerialId.startsWith("HH-P-"));
    const propId = createRes.body.id;

    // 3. Step 3 & 4: Update address & current_step
    const updateAddress = await call("PUT", `/api/properties/${propId}`, {
      token,
      org: orgId,
      body: {
        current_step: "property_address",
        step_number: 4,
        address: {
          formattedAddress: "Tungarli, Lonavala, Maharashtra",
          streetName: "Tungarli Road",
          city: "Lonavala",
          state: "Maharashtra",
          postalCode: "410401",
          country: "India",
        },
      },
    });
    assert.equal(updateAddress.status, 200);
    assert.equal(updateAddress.body.current_step, "property_address");
    assert.equal(updateAddress.body.location, "Tungarli, Lonavala, Maharashtra");

    // 4. Step 5: Upload photo
    const photoRes = await call("POST", `/api/properties/${propId}/photos`, {
      token,
      org: orgId,
      body: { data: PNG_1PX },
    });
    assert.equal(photoRes.status, 200);
    assert.ok(photoRes.body.url.startsWith("/media/properties/"));
    assert.equal(photoRes.body.photos.length, 1);

    // 5. Update remaining steps
    const updateDetails = await call("PUT", `/api/properties/${propId}`, {
      token,
      org: orgId,
      body: {
        current_step: "property_price",
        step_number: 13,
        title: "Tungarli Luxury Retreat",
        basePrice: 8500,
        capacity: { guests: 8, bedrooms: 4, beds: 5, bathrooms: 4 },
        amenities: ["Wifi", "Private Pool", "Kitchen", "Free Parking", "Air Conditioning"],
        uniqueness: ["Mountain View", "Private Pool"],
        instantBooking: true,
        cancellationPolicy: "flexible",
      },
    });
    assert.equal(updateDetails.status, 200);
    assert.equal(updateDetails.body.title, "Tungarli Luxury Retreat");
    assert.equal(updateDetails.body.basePrice, 8500);

    // 6. Get single property and list properties
    const getRes = await call("GET", `/api/properties/${propId}`, { token, org: orgId });
    assert.equal(getRes.status, 200);
    assert.equal(getRes.body.title, "Tungarli Luxury Retreat");

    const listRes = await call("GET", "/api/properties", { token, org: orgId });
    assert.equal(listRes.status, 200);
    assert.equal(listRes.body.length, 1);

    // 7. Publish property
    const publishRes = await call("POST", `/api/properties/${propId}/publish`, {
      token,
      org: orgId,
    });
    assert.equal(publishRes.status, 200);
    assert.equal(publishRes.body.ok, true);
    assert.equal(publishRes.body.property.status, "activated");
  });
});

test("properties: protected fields, search/filter, rooms & units, publish slug, activity, roles", async (t) => {
  const db = memoryDb(t);
  const fakes = fakeServices();

  await withServer(db, fakes.services, async (call) => {
    const owner = await signUp(call, fakes, { name: "Asha Host", email: "asha@example.com" });
    const token = owner.access_token;
    const org = owner.memberships[0].org_id;

    // A client cannot set status / org / serial through a create or update payload.
    const created = await call("POST", "/api/properties", {
      token, org, body: { property_type: "Cottage", status: "activated", org_id: 999, propertySerialId: "HACK" },
    });
    assert.equal(created.status, 201);
    assert.equal(created.body.status, "draft");
    assert.equal(created.body.org_id, org);
    assert.notEqual(created.body.propertySerialId, "HACK");
    assert.equal(created.body.property_type, "Cottage", "snake_case alias for the Flutter client");
    const id = created.body.id;

    const sneaky = await call("PUT", `/api/properties/${id}`, { token, org, body: { status: "activated", slug: "x" } });
    assert.equal(sneaky.body.status, "draft");
    assert.equal(sneaky.body.slug, null);

    // snake_case wizard payload is stored canonically and read back.
    const saved = await call("PUT", `/api/properties/${id}`, {
      token, org,
      body: { title: "Pine Cottage", base_price: 4500, guests: 4, bedrooms: 2, advance_percent: 30, extra_guest_charge: 800,
        address: { formattedAddress: "Mall Road, Manali", city: "Manali", state: "Himachal Pradesh" } },
    });
    assert.equal(saved.status, 200);
    assert.equal(saved.body.basePrice, 4500);
    assert.equal(saved.body.base_price, 4500);
    assert.equal(saved.body.capacity.guests, 4);
    assert.equal(saved.body.advance_percent, 30);
    assert.equal(saved.body.city, "Manali");

    const bad = await call("PUT", `/api/properties/${id}`, { token, org, body: { advance_percent: 150 } });
    assert.equal(bad.status, 400);
    const longTitle = await call("PUT", `/api/properties/${id}`, { token, org, body: { title: "x".repeat(101) } });
    assert.equal(longTitle.status, 400);

    // Rooms & units
    const room = await call("POST", `/api/properties/${id}/rooms`, {
      token, org, body: { name: "Deluxe Room", room_type: "room", max_adults: 2, max_children: 1, unit_count: 3 },
    });
    assert.equal(room.status, 201);
    assert.equal(room.body.max_guests, 3);
    assert.equal(room.body.effective_price, 4500, "inherits the property price");
    const dup = await call("POST", `/api/properties/${id}/rooms`, { token, org, body: { name: "deluxe room" } });
    assert.equal(dup.status, 409);
    const noName = await call("POST", `/api/properties/${id}/rooms`, { token, org, body: { unit_count: 2 } });
    assert.equal(noName.status, 400);
    const suite = await call("POST", `/api/properties/${id}/rooms`, {
      token, org, body: { name: "Family Suite", room_type: "suite", max_adults: 4, unit_count: 1, base_price: 7000 },
    });
    assert.equal(suite.body.effective_price, 7000);
    const edited = await call("PATCH", `/api/properties/${id}/rooms/${room.body.id}`, { token, org, body: { unit_count: 4 } });
    assert.equal(edited.body.unit_count, 4);

    // Search and status filter (All Properties)
    await call("POST", "/api/properties", { token, org, body: { title: "Goa Beach House" } });
    const search = await call("GET", "/api/properties?q=manali", { token, org });
    assert.deepEqual(search.body.map((p) => p.title), ["Pine Cottage"]);
    assert.equal(search.body[0].room_count, 2);
    assert.equal(search.body[0].unit_count, 5);

    // Publish assigns a unique slug + booking URL.
    const pub = await call("POST", `/api/properties/${id}/publish`, { token, org });
    assert.equal(pub.status, 200);
    assert.equal(pub.body.property.status, "activated");
    assert.equal(pub.body.property.slug, "pine-cottage");
    assert.match(pub.body.property.booking_url, /\/p\/pine-cottage$/);
    const live = await call("GET", "/api/properties?status=activated", { token, org });
    assert.equal(live.body.length, 1);

    // Address is locked once live.
    const relocate = await call("PUT", `/api/properties/${id}`, { token, org, body: { address: { city: "Goa" } } });
    assert.equal(relocate.body.city, "Manali");

    // Entire-place listing with no rooms gets one unit on publish; no price → refused.
    const villa = await call("POST", "/api/properties", { token, org, body: { title: "Pine Cottage" } });
    const noPrice = await call("POST", `/api/properties/${villa.body.id}/publish`, { token, org });
    assert.equal(noPrice.status, 400);
    await call("PUT", `/api/properties/${villa.body.id}`, { token, org, body: { base_price: 9000 } });
    const villaPub = await call("POST", `/api/properties/${villa.body.id}/publish`, { token, org });
    assert.equal(villaPub.body.property.rooms.length, 1);
    assert.equal(villaPub.body.property.rooms[0].room_type, "entire_place");
    assert.equal(villaPub.body.property.slug, "pine-cottage-2", "slugs are unique");

    // Archive rooms; a live property keeps at least one.
    const arch = await call("DELETE", `/api/properties/${id}/rooms/${suite.body.id}`, { token, org });
    assert.equal(arch.status, 204);
    const last = await call("DELETE", `/api/properties/${id}/rooms/${room.body.id}`, { token, org });
    assert.equal(last.status, 409);
    const rooms = await call("GET", `/api/properties/${id}/rooms`, { token, org });
    assert.equal(rooms.body.length, 1);

    // Activity log
    const activity = await call("GET", `/api/properties/${id}/activity`, { token, org });
    assert.ok(activity.body.some((a) => a.action === "published"));
    assert.ok(activity.body.some((a) => a.action === "room_added"));
    assert.equal(activity.body[0].user_name, "Asha Host");

    // Another organisation can't see or touch it.
    const other = await signUp(call, fakes, { name: "Other Host", email: "other@example.com" });
    const peek = await call("GET", `/api/properties/${id}`, { token: other.access_token, org });
    assert.equal(peek.status, 404);
    const peekOwnOrg = await call("GET", `/api/properties/${id}/rooms`, {
      token: other.access_token, org: other.memberships[0].org_id,
    });
    assert.equal(peekOwnOrg.status, 404);

    // Read-only members can read but not write.
    await call("POST", `/api/orgs/${org}/invites`, { token, body: { email: "viewer@example.com", role: "read_only" } });
    const inviteToken = decodeURIComponent(fakes.mail.at(-1).text.match(/invite_token=(\S+)/)[1]);
    await call("POST", "/api/auth/signup/request-otp", { body: { name: "View Er", email: "viewer@example.com" } });
    const viewer = (await call("POST", "/api/auth/signup/verify-otp", {
      body: { email: "viewer@example.com", code: codeFrom(fakes.mail), invite_token: inviteToken },
    })).body;
    const vRead = await call("GET", "/api/properties", { token: viewer.access_token, org });
    assert.equal(vRead.status, 200);
    const vWrite = await call("POST", `/api/properties/${id}/rooms`, { token: viewer.access_token, org, body: { name: "Hack" } });
    assert.equal(vWrite.status, 403);
  });
});
