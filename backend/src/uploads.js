import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

import { config } from "./config.js";

/** Photos are stored next to the data file and served from /media. */
export const uploadsDir = path.resolve(path.dirname(path.resolve(config.dataFile)), "uploads");

const MAX_BYTES = 5 * 1024 * 1024;

/** Detects the image type from its first bytes (never trust the filename). */
function sniff(buffer) {
  if (buffer.length > 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return "jpg";
  if (buffer.length > 8 && buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return "png";
  if (buffer.length > 12 && buffer.toString("ascii", 0, 4) === "RIFF" && buffer.toString("ascii", 8, 12) === "WEBP") return "webp";
  return null;
}

/**
 * Saves a base64 image into /media/<folder>. Returns `{ url }` (a path with an
 * unguessable name) or `{ error }`.
 */
export async function savePhoto(folder, body) {
  const raw = String(body?.data || "").replace(/^data:[^;]+;base64,/, "");
  if (!raw) return { error: "No image received" };
  let buffer;
  try {
    buffer = Buffer.from(raw, "base64");
  } catch {
    return { error: "Couldn't read that image" };
  }
  if (buffer.length > MAX_BYTES) return { error: "The photo must be 5 MB or smaller" };
  const ext = sniff(buffer);
  if (!ext) return { error: "Use a JPG, PNG or WebP photo" };

  const dir = path.join(uploadsDir, String(folder));
  await fs.mkdir(dir, { recursive: true });
  const name = `${crypto.randomBytes(16).toString("hex")}.${ext}`;
  await fs.writeFile(path.join(dir, name), buffer);
  return { url: `/media/${folder}/${name}` };
}
