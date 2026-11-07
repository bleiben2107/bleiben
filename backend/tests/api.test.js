import assert from "node:assert/strict";
import test from "node:test";

import { createApp } from "../src/app.js";
import { createDb } from "../src/db.js";

function memoryDb() {
  return createDb(`./data/test-${process.pid}-${Date.now()}.json`);
}

async function withServer(db, run) {
  const app = createApp(db);
  const server = app.listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  const { port } = server.address();
  try {
    await run(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("health check", async () => {
  await withServer(memoryDb(), async (base) => {
    const response = await fetch(`${base}/api/health`);
    const body = await response.json();
    assert.equal(response.status, 200);
    assert.equal(body.status, "ok");
  });
});

test("register, login, and stays crud", async () => {
  await withServer(memoryDb(), async (base) => {
    const register = await fetch(`${base}/api/auth/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "Ada", email: "ada@bleiben.app", password: "secret12" }),
    });
    assert.equal(register.status, 201);
    const token = (await register.json()).access_token;
    const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };

    const created = await fetch(`${base}/api/stays`, {
      method: "POST",
      headers,
      body: JSON.stringify({ title: "Lake cabin", location: "Como", notes: "Quiet week" }),
    });
    assert.equal(created.status, 201);
    const stayId = (await created.json()).id;

    const listed = await fetch(`${base}/api/stays`, { headers });
    assert.equal(listed.status, 200);
    assert.equal((await listed.json()).length, 1);

    const updated = await fetch(`${base}/api/stays/${stayId}`, {
      method: "PATCH",
      headers,
      body: JSON.stringify({ notes: "Bring books" }),
    });
    assert.equal(updated.status, 200);
    assert.equal((await updated.json()).notes, "Bring books");

    const deleted = await fetch(`${base}/api/stays/${stayId}`, { method: "DELETE", headers });
    assert.equal(deleted.status, 204);
  });
});
