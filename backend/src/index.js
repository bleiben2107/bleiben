import { config } from "./config.js";
import { createApp } from "./app.js";
import { createDb, createMongoDb } from "./db.js";
import { expireHolds } from "./routes/bookings.js";
import { dispatchScheduled } from "./routes/messages.js";
import { billingReminders } from "./routes/billing.js";
import { syncDueConnections } from "./routes/channels.js";
import { createMailer, createSmsSender } from "./messaging.js";

let db;
if (config.mongodbUri) {
  try {
    db = await createMongoDb(config.mongodbUri, config.mongodbDb);
  } catch (err) {
    console.error(`[MongoDB] Connection failed: ${err.message}`);
    console.error(
      "[MongoDB] Check Atlas Network Access (IP Access List) and confirm the cluster is active.",
    );
    console.warn(`[MongoDB] Falling back to local JSON store (${config.dataFile}).`);
    db = createDb();
  }
} else {
  db = createDb();
}
const app = createApp(db);

// Release 15-minute booking holds that were never paid (MVP plan §2).
setInterval(() => {
  expireHolds(db).catch((err) => console.error("[holds]", err.message));
  // Scheduled guest messages (held if the booking changed).
  dispatchScheduled(db).catch((err) => console.error("[scheduled]", err.message));
}, 60_000).unref();

// iCal calendar sync (each connection every 30 min, backoff on errors) and
// subscription reminders (trial/plan ending, read-only grace).
const workerServices = { mailer: createMailer(), sms: createSmsSender() };
let syncing = false;
setInterval(async () => {
  if (syncing) return;
  syncing = true;
  try {
    await syncDueConnections(db, workerServices);
  } catch (err) {
    console.error("[ical]", err.message);
  } finally {
    syncing = false;
  }
}, 5 * 60_000).unref();
setInterval(() => {
  billingReminders(db, workerServices).catch((err) => console.error("[billing]", err.message));
}, 60 * 60_000).unref();

const green = (text) => `\x1b[32m${text}\x1b[0m`;
const yellow = (text) => `\x1b[33m${text}\x1b[0m`;
const dim = (text) => `\x1b[2m${text}\x1b[0m`;

const server = app.listen(config.port, "0.0.0.0", () => {
  const status =
    db.kind === "mongodb"
      ? `${green("✔ MongoDB connected")} ${dim(`(${db.dbName})`)}`
      : yellow(`[!] Local JSON store (${config.dataFile})`);
  console.log(`${config.appName} API running on http://localhost:${config.port}`);
  console.log(status);
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    server.close(async () => {
      await db.close?.();
      process.exit(0);
    });
  });
}
