import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { createApp } from "../src/app.js";
import { createDb } from "../src/db.js";

function memoryDb(t) {
  const filePath = `./data/test-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.json`;
  t.after(() => fs.rmSync(filePath, { force: true }));
  return createDb(filePath);
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

test("health check", async (t) => {
  await withServer(memoryDb(t), async (base) => {
    const response = await fetch(`${base}/api/health`);
    const body = await response.json();
    assert.equal(response.status, 200);
    assert.equal(body.status, "ok");
  });
});

test("cors allows configured frontend origin and blocks others", async (t) => {
  await withServer(memoryDb(t), async (base) => {
    const allowed = await fetch(`${base}/api/health`, {
      headers: { Origin: "http://localhost:3000" },
    });
    assert.equal(allowed.headers.get("access-control-allow-origin"), "http://localhost:3000");

    const blocked = await fetch(`${base}/api/health`, {
      headers: { Origin: "https://evil.example" },
    });
    assert.equal(blocked.headers.get("access-control-allow-origin"), null);

    // flutter run -d chrome uses a random localhost port in development.
    const devPort = await fetch(`${base}/api/health`, {
      headers: { Origin: "http://localhost:53172" },
    });
    assert.equal(devPort.headers.get("access-control-allow-origin"), "http://localhost:53172");
  });
});
