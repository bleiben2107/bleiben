import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { createApp } from "../src/app.js";
import { createDb } from "../src/db.js";
import { EmailDeliveryError } from "../src/messaging.js";
import { can, canAssign } from "../src/roles.js";

// 1×1 PNG, for photo upload tests.
const PNG_1PX =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

function memoryDb(t) {
  const filePath = `./data/test-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.json`;
  t.after(() => fs.rmSync(filePath, { force: true }));
  return createDb(filePath);
}

/** Captures outgoing email/SMS instead of sending them. */
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
const linkToken = (mailList, param) =>
  decodeURIComponent(mailList.at(-1).text.match(new RegExp(`${param}=(\\S+)`))[1]);

/** Signs up with email OTP; returns the session body. */
async function signUp(call, fakes, { name, email, phone, inviteToken }) {
  const req = await call("POST", "/api/auth/signup/request-otp", {
    body: { name, email, phone, country_code: "+91" },
  });
  assert.equal(req.status, 202, JSON.stringify(req.body));
  const ver = await call("POST", "/api/auth/signup/verify-otp", {
    body: { email, code: codeFrom(fakes.mail), invite_token: inviteToken },
  });
  assert.equal(ver.status, 201, JSON.stringify(ver.body));
  return ver.body;
}

/** Logs in with email or phone + OTP; returns the session body. */
async function logIn(call, fakes, identifier) {
  const req = await call("POST", "/api/auth/login/request-otp", { body: { identifier, country_code: "+91" } });
  assert.equal(req.status, 202, JSON.stringify(req.body));
  const source = req.body.channel === "phone" ? fakes.sms : fakes.mail;
  const ver = await call("POST", "/api/auth/login/verify-otp", {
    body: { identifier, country_code: "+91", code: codeFrom(source) },
  });
  assert.equal(ver.status, 200, JSON.stringify(ver.body));
  return ver.body;
}

test("role matrix", () => {
  assert.ok(can("owner", "billing.manage"));
  assert.ok(!can("manager", "billing.manage"));
  assert.ok(can("manager", "team.manage"));
  assert.ok(!can("staff", "team.manage"));
  assert.ok(can("read_only", "team.read"));
  assert.ok(canAssign("owner", "owner"));
  assert.ok(!canAssign("manager", "owner"));
  assert.ok(canAssign("manager", "staff"));
  assert.ok(!canAssign("staff", "read_only"));
});

test("sign up: name + email required, phone optional, OTP emailed, account + organisation created", async (t) => {
  const fakes = fakeServices();
  await withServer(memoryDb(t), fakes.services, async (call) => {
    const noEmail = await call("POST", "/api/auth/signup/request-otp", { body: { name: "Asha Rao" } });
    assert.equal(noEmail.status, 400);
    const badName = await call("POST", "/api/auth/signup/request-otp", { body: { name: "Asha99", email: "a@b.co" } });
    assert.match(badName.body.detail, /Only alphabets/);
    const badPhone = await call("POST", "/api/auth/signup/request-otp", {
      body: { name: "Asha Rao", email: "a@b.co", phone: "123" },
    });
    assert.equal(badPhone.status, 400);

    const req = await call("POST", "/api/auth/signup/request-otp", {
      body: { name: "Asha  Rao", email: "Asha@HillHomes.in", phone: "98765 43210", country_code: "+91" },
    });
    assert.equal(req.status, 202);
    assert.equal(req.body.dev_code, undefined, "OTP must not leak when email is configured");
    assert.equal(fakes.mail.at(-1).to, "asha@hillhomes.in");
    assert.match(fakes.mail.at(-1).subject, /^\d{6} is your Bleiben verification code$/);

    const again = await call("POST", "/api/auth/signup/request-otp", {
      body: { name: "Asha Rao", email: "asha@hillhomes.in" },
    });
    assert.equal(again.status, 429, "resend cooldown");

    const wrong = await call("POST", "/api/auth/signup/verify-otp", {
      body: { email: "asha@hillhomes.in", code: "000000" },
    });
    assert.match(wrong.body.detail, /4 attempts left/);

    const code = codeFrom(fakes.mail);
    const ok = await call("POST", "/api/auth/signup/verify-otp", { body: { email: "asha@hillhomes.in", code } });
    assert.equal(ok.status, 201);
    assert.equal(ok.body.user.name, "Asha Rao");
    assert.equal(ok.body.user.email_verified, true);
    assert.equal(ok.body.user.phone, "+919876543210");
    // PRD AUTH-3: the organisation is provisioned automatically, user is Owner.
    assert.equal(ok.body.memberships.length, 1);
    assert.equal(ok.body.memberships[0].role, "owner");
    assert.equal(ok.body.memberships[0].org_name, "Asha Rao");

    const reuse = await call("POST", "/api/auth/signup/verify-otp", { body: { email: "asha@hillhomes.in", code } });
    assert.equal(reuse.status, 400, "OTPs are single use");

    const dupEmail = await call("POST", "/api/auth/signup/request-otp", {
      body: { name: "Other Person", email: "asha@hillhomes.in" },
    });
    assert.equal(dupEmail.status, 409);
    assert.equal(dupEmail.body.action, "login");
  });
});

test("login: email or phone OTP; unknown accounts sent to sign up; no duplicate organisation", async (t) => {
  const fakes = fakeServices();
  await withServer(memoryDb(t), fakes.services, async (call) => {
    const unknown = await call("POST", "/api/auth/login/request-otp", { body: { identifier: "nobody@x.in" } });
    assert.equal(unknown.status, 404);
    assert.equal(unknown.body.action, "signup");

    await signUp(call, fakes, { name: "Asha Rao", email: "asha@hillhomes.in", phone: "9876543210" });

    const byEmail = await logIn(call, fakes, "ASHA@hillhomes.in");
    assert.equal(byEmail.user.name, "Asha Rao");
    assert.equal(byEmail.memberships.length, 1, "login doesn't create a second organisation");

    const byPhone = await logIn(call, fakes, "98765 43210");
    assert.equal(byPhone.user.phone_verified, true);
  });
});

test("OTP locks after too many wrong attempts", async (t) => {
  const fakes = fakeServices();
  await withServer(memoryDb(t), fakes.services, async (call) => {
    await call("POST", "/api/auth/signup/request-otp", { body: { name: "Lock Test", email: "lock@x.in" } });
    for (let i = 0; i < 5; i += 1) {
      await call("POST", "/api/auth/signup/verify-otp", { body: { email: "lock@x.in", code: "111111" } });
    }
    const locked = await call("POST", "/api/auth/signup/verify-otp", {
      body: { email: "lock@x.in", code: codeFrom(fakes.mail) },
    });
    assert.equal(locked.status, 429);
  });
});

test("dev mode returns the OTP when no email/SMS provider is configured", async (t) => {
  const services = {
    mailer: { configured: false, send: async () => ({ delivered: false }) },
    sms: { configured: false, send: async () => ({ delivered: false }) },
  };
  await withServer(memoryDb(t), services, async (call) => {
    const res = await call("POST", "/api/auth/signup/request-otp", { body: { name: "Dev User", email: "dev@x.in" } });
    assert.match(res.body.dev_code, /^\d{6}$/);
  });
});

test("account settings: personal info, profile photo, change email / add phone with OTP", async (t) => {
  const fakes = fakeServices();
  await withServer(memoryDb(t), fakes.services, async (call) => {
    const asha = await signUp(call, fakes, { name: "Asha Rao", email: "asha@hillhomes.in" });
    const token = asha.access_token;
    await signUp(call, fakes, { name: "Ravi Kumar", email: "ravi@hillhomes.in", phone: "9811111111" });

    const anon = await call("GET", "/api/account");
    assert.equal(anon.status, 401);

    const missing = await call("PATCH", "/api/account/profile", { token, body: { first_name: "" } });
    assert.match(missing.body.detail, /First name is required/);
    const badPin = await call("PATCH", "/api/account/profile", { token, body: { first_name: "Asha", pincode: "12" } });
    assert.match(badPin.body.detail, /Pincode/);
    const longAbout = await call("PATCH", "/api/account/profile", {
      token,
      body: { first_name: "Asha", about: "x".repeat(501) },
    });
    assert.equal(longAbout.status, 400);

    const saved = await call("PATCH", "/api/account/profile", {
      token,
      body: {
        first_name: "Asha",
        last_name: "Menon",
        preferred_name: "Ash",
        date_of_birth: "1990-04-12",
        city: "Kochi",
        pincode: "682001",
        about: "Host in Kerala",
        email_notifications: false,
      },
    });
    assert.equal(saved.status, 200, JSON.stringify(saved.body));
    assert.equal(saved.body.name, "Asha Menon");
    assert.equal(saved.body.profile.preferred_name, "Ash");
    assert.equal(saved.body.profile.email_notifications, false);
    const me = await call("GET", "/api/auth/me", { token });
    assert.equal(me.body.profile.city, "Kochi");

    const notImage = await call("POST", "/api/account/avatar", { token, body: { data: "aGVsbG8=" } });
    assert.equal(notImage.status, 400);
    const avatar = await call("POST", "/api/account/avatar", { token, body: { data: PNG_1PX } });
    assert.equal(avatar.status, 200);
    assert.match(avatar.body.avatar_url, /^\/media\/avatars\/[0-9a-f]{32}\.png$/);

    // Change email: OTP goes to the NEW address; taken addresses are refused.
    const taken = await call("POST", "/api/account/contact/request-otp", {
      token,
      body: { channel: "email", value: "ravi@hillhomes.in" },
    });
    assert.equal(taken.status, 409);
    const req = await call("POST", "/api/account/contact/request-otp", {
      token,
      body: { channel: "email", value: "asha@new.in" },
    });
    assert.equal(req.status, 202);
    assert.equal(fakes.mail.at(-1).to, "asha@new.in");
    const changed = await call("POST", "/api/account/contact/verify-otp", {
      token,
      body: { channel: "email", value: "asha@new.in", code: codeFrom(fakes.mail) },
    });
    assert.equal(changed.status, 200);
    assert.equal(changed.body.email, "asha@new.in");
    assert.equal(changed.body.email_verified, true);

    // Add phone via SMS OTP → verified.
    const phoneTaken = await call("POST", "/api/account/contact/request-otp", {
      token,
      body: { channel: "phone", value: "9811111111", country_code: "+91" },
    });
    assert.equal(phoneTaken.status, 409);
    await call("POST", "/api/account/contact/request-otp", {
      token,
      body: { channel: "phone", value: "9822222222", country_code: "+91" },
    });
    const wrong = await call("POST", "/api/account/contact/verify-otp", {
      token,
      body: { channel: "phone", value: "9822222222", country_code: "+91", code: "000000" },
    });
    assert.equal(wrong.status, 400);
    const added = await call("POST", "/api/account/contact/verify-otp", {
      token,
      body: { channel: "phone", value: "9822222222", country_code: "+91", code: codeFrom(fakes.sms) },
    });
    assert.equal(added.body.phone, "+919822222222");
    assert.equal(added.body.phone_verified, true);

    // Log in with the new email works; the old one no longer exists.
    await logIn(call, fakes, "asha@new.in");
    const old = await call("POST", "/api/auth/login/request-otp", { body: { identifier: "asha@hillhomes.in" } });
    assert.equal(old.status, 404);
  });
});

test("invites: join at sign-up, role enforcement and last-owner protection", async (t) => {
  const fakes = fakeServices();
  await withServer(memoryDb(t), fakes.services, async (call) => {
    const owner = await signUp(call, fakes, { name: "Lake Owner", email: "owner@lake.in" });
    const ownerToken = owner.access_token;
    const orgId = owner.memberships[0].org_id;
    await call("PATCH", `/api/orgs/${orgId}`, { token: ownerToken, body: { name: "Lake Stays" } });

    const invite = await call("POST", `/api/orgs/${orgId}/invites`, {
      token: ownerToken,
      body: { email: "mgr@lake.in", role: "manager" },
    });
    assert.equal(invite.status, 201);
    const managerInvite = linkToken(fakes.mail, "invite_token");

    const preview = await call("POST", "/api/invites/preview", { token: ownerToken, body: { token: managerInvite } });
    assert.equal(preview.body.org_name, "Lake Stays");

    // Signing up from an invite joins that organisation instead of creating one.
    const manager = await signUp(call, fakes, { name: "Lake Manager", email: "mgr@lake.in", inviteToken: managerInvite });
    assert.equal(manager.invite, "accepted");
    assert.equal(manager.memberships.length, 1);
    assert.equal(manager.memberships[0].org_id, orgId);
    assert.equal(manager.memberships[0].role, "manager");

    const noOwner = await call("POST", `/api/orgs/${orgId}/invites`, {
      token: manager.access_token,
      body: { email: "boss@lake.in", role: "owner" },
    });
    assert.equal(noOwner.status, 403);

    await call("POST", `/api/orgs/${orgId}/invites`, {
      token: manager.access_token,
      body: { email: "viewer@lake.in", role: "read_only" },
    });
    const viewerInvite = linkToken(fakes.mail, "invite_token");
    const viewer = await signUp(call, fakes, { name: "Lake Viewer", email: "viewer@lake.in", inviteToken: viewerInvite });
    assert.equal(viewer.memberships[0].role, "read_only");

    const reuse = await call("POST", "/api/invites/accept", { token: ownerToken, body: { token: viewerInvite } });
    assert.equal(reuse.status, 404);

    // Someone signed in with a different email can't take an invite.
    await call("POST", `/api/orgs/${orgId}/invites`, { token: ownerToken, body: { email: "staffer@lake.in", role: "staff" } });
    const stafferInvite = linkToken(fakes.mail, "invite_token");
    const wrongPerson = await call("POST", "/api/invites/accept", { token: viewer.access_token, body: { token: stafferInvite } });
    assert.equal(wrongPerson.status, 409);

    const read = await call("GET", `/api/orgs/${orgId}/members`, { token: viewer.access_token });
    assert.equal(read.status, 200);
    const write = await call("POST", `/api/orgs/${orgId}/invites`, {
      token: viewer.access_token,
      body: { email: "x@y.in", role: "staff" },
    });
    assert.equal(write.status, 403);
    const rename = await call("PATCH", `/api/orgs/${orgId}`, { token: viewer.access_token, body: { name: "Mine now" } });
    assert.equal(rename.status, 403);

    const members = await call("GET", `/api/orgs/${orgId}/members`, { token: ownerToken });
    assert.equal(members.body.filter((m) => m.status === "active").length, 3);
    const viewerMember = members.body.find((m) => m.role === "read_only");
    const promoted = await call("PATCH", `/api/orgs/${orgId}/members/${viewerMember.id}`, {
      token: ownerToken,
      body: { role: "staff" },
    });
    assert.equal(promoted.body.role, "staff");

    const ownerMember = members.body.find((m) => m.role === "owner");
    const demote = await call("PATCH", `/api/orgs/${orgId}/members/${ownerMember.id}`, {
      token: ownerToken,
      body: { role: "manager" },
    });
    assert.equal(demote.status, 409);

    const outsider = await signUp(call, fakes, { name: "Out Sider", email: "out@x.in" });
    const peek = await call("GET", `/api/orgs/${orgId}`, { token: outsider.access_token });
    assert.equal(peek.status, 404);

    const remove = await call("DELETE", `/api/orgs/${orgId}/members/${viewerMember.id}`, { token: ownerToken });
    assert.equal(remove.status, 204);
    const after = await call("GET", `/api/orgs/${orgId}`, { token: viewer.access_token });
    assert.equal(after.status, 404);
  });
});

test("email delivery failure returns 502 instead of crashing", async (t) => {
  const services = {
    mailer: {
      configured: true,
      send: async () => {
        throw new EmailDeliveryError(new Error("535"));
      },
    },
    sms: { configured: true, send: async () => ({ delivered: true }) },
  };
  await withServer(memoryDb(t), services, async (call) => {
    const res = await call("POST", "/api/auth/signup/request-otp", { body: { name: "A B", email: "a@b.co" } });
    assert.equal(res.status, 502);
  });
});
