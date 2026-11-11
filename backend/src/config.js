import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import dotenv from "dotenv";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const envPath = path.resolve(__dirname, "../.env");
if (fs.existsSync(envPath)) {
  dotenv.config({ path: envPath, quiet: true });
}

const nodeEnv = process.env.NODE_ENV || "development";

export const config = {
  nodeEnv,
  isProduction: nodeEnv === "production",
  port: Number(process.env.PORT || 8000),
  appName: process.env.APP_NAME || "Bleiben",
  secretKey: process.env.SECRET_KEY || "bleiben-dev-secret-change-me",
  tokenExpireMinutes: Number(process.env.ACCESS_TOKEN_EXPIRE_MINUTES || 60 * 24 * 7),
  dataFile: process.env.DATA_FILE || "./data/bleiben.json",
  corsOrigins: process.env.CORS_ORIGINS ?? "http://localhost:3000,http://127.0.0.1:3000",
  // USE_LOCAL_STORE=1 forces the JSON file store (e.g. local testing without
  // touching the shared MongoDB).
  mongodbUri: process.env.USE_LOCAL_STORE === "1" ? "" : process.env.MONGODB_URI || "",
  mongodbDb: process.env.MONGODB_DB || "bleiben",

  // Where the Flutter web app is served; used to build invite links.
  appBaseUrl: (process.env.APP_BASE_URL || "http://127.0.0.1:5180").replace(/\/+$/, ""),

  smtp: {
    host: process.env.SMTP_HOST || "",
    port: Number(process.env.SMTP_PORT || 587),
    secure: process.env.SMTP_SECURE === "true",
    user: process.env.SMTP_USER || "",
    pass: process.env.SMTP_PASS || "",
    from: process.env.MAIL_FROM || "Bleiben <no-reply@bleiben.co.in>",
  },

  // No SMS provider is wired yet. Until one is, OTPs are logged and, outside
  // production, returned to the client as `dev_code` so local testing works.
  sms: {
    provider: process.env.SMS_PROVIDER || "",
  },

  otp: {
    length: 6,
    ttlSeconds: Number(process.env.OTP_TTL_SECONDS || 600),
    resendCooldownSeconds: Number(process.env.OTP_RESEND_SECONDS || 60),
    maxSendsPerHour: Number(process.env.OTP_MAX_SENDS_PER_HOUR || 5),
    maxAttempts: Number(process.env.OTP_MAX_ATTEMPTS || 5),
  },
  inviteTtlDays: Number(process.env.INVITE_TTL_DAYS || 7),
};

const LOCAL_ORIGIN = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

export function corsOriginList() {
  const raw = config.corsOrigins.trim();
  if (raw === "*") {
    return "*";
  }
  const allowed = raw
    .split(",")
    .map((origin) => origin.trim().replace(/\/+$/, ""))
    .filter(Boolean);
  if (config.isProduction) {
    return allowed;
  }
  // Outside production also allow any localhost port, since `flutter run -d
  // chrome` serves the app on a random port.
  return (origin, callback) => callback(null, !origin || allowed.includes(origin) || LOCAL_ORIGIN.test(origin));
}
