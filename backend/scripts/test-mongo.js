import { config } from "../src/config.js";
import { createMongoDb } from "../src/db.js";

if (!config.mongodbUri) {
  console.error("MONGODB_URI is not set in backend/.env");
  process.exit(1);
}

const db = await createMongoDb(config.mongodbUri, config.mongodbDb);
try {
  await db.ping();
  console.log(`Connected to MongoDB database "${db.dbName}" successfully.`);
} finally {
  await db.close();
}

