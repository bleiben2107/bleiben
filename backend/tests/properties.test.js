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
