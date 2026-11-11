import crypto from "node:crypto";

import { config } from "./config.js";

/** Keyed hash for OTPs and link tokens; only hashes are ever stored. */
export function hashSecret(value) {
  return crypto.createHmac("sha256", config.secretKey).update(String(value)).digest("hex");
}

export function secretsMatch(value, storedHash) {
  const candidate = Buffer.from(hashSecret(value), "hex");
  const stored = Buffer.from(String(storedHash), "hex");
  return candidate.length === stored.length && crypto.timingSafeEqual(candidate, stored);
}

export function generateOtp(length = config.otp.length) {
  let code = "";
  for (let i = 0; i < length; i += 1) {
    code += crypto.randomInt(0, 10);
  }
  return code;
}

export function generateToken() {
  return crypto.randomBytes(32).toString("base64url");
}

/** "+91 98765 43210" / "9876543210" + "+91" → "+919876543210", or null. */
export function normalizePhone(phone, countryCode = "+91") {
  const digits = String(phone || "").replace(/[^\d+]/g, "");
  if (!digits) {
    return null;
  }
  const withCountry = digits.startsWith("+")
    ? digits
    : `${String(countryCode || "+91").replace(/[^\d+]/g, "")}${digits.replace(/^0+/, "")}`;
  return /^\+[1-9]\d{7,14}$/.test(withCountry) ? withCountry : null;
}

export function normalizeEmail(email) {
  const value = String(email || "").toLowerCase().trim();
  return /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/.test(value) ? value : null;
}

export function maskPhone(phone) {
  return phone.length > 6 ? `${phone.slice(0, 3)}••••${phone.slice(-3)}` : phone;
}
