import { config } from "./config.js";
import { createApp } from "./app.js";
import { createDb, createMongoDb } from "./db.js";

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
