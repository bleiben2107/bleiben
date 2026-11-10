import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import dotenv from "dotenv";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const envPath = path.resolve(__dirname, "../.env");
if (fs.existsSync(envPath)) {
  dotenv.config({ path: envPath, quiet: true });
}

export const config = {
  port: Number(process.env.PORT || 8000),
  appName: process.env.APP_NAME || "Bleiben",
  secretKey: process.env.SECRET_KEY || "bleiben-dev-secret-change-me",
  tokenExpireMinutes: Number(process.env.ACCESS_TOKEN_EXPIRE_MINUTES || 60 * 24 * 7),
  dataFile: process.env.DATA_FILE || "./data/bleiben.json",
  corsOrigins: process.env.CORS_ORIGINS ?? "http://localhost:3000,http://127.0.0.1:3000",
  mongodbUri: process.env.MONGODB_URI || "",
  mongodbDb: process.env.MONGODB_DB || "bleiben",
};

export function corsOriginList() {
  const raw = config.corsOrigins.trim();
  if (raw === "*") {
    return "*";
  }
  return raw
    .split(",")
    .map((origin) => origin.trim().replace(/\/+$/, ""))
    .filter(Boolean);
}
