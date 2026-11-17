import dns from "node:dns/promises";
import net from "node:net";

import { config } from "../config.js";

/** Minimal RFC 5545 reader/writer for availability calendars (Airbnb, Booking.com, Vrbo…). */

const DAY = 86400000;
const fmtDate = (d) => d.toISOString().slice(0, 10);
const ymdToIcs = (s) => s.replaceAll("-", "");

function toYmd(v) {
  const m = /^(\d{4})(\d{2})(\d{2})/.exec(String(v).trim());
  return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
}

function unescapeText(s) {
  return String(s).replace(/\\n/gi, "\n").replace(/\\([,;\\])/g, "$1");
}

/** Parses VEVENTs → [{ uid, start, end (exclusive), summary, description, status }]. */
export function parseIcs(text) {
  const raw = String(text ?? "");
  if (!/BEGIN:VCALENDAR/i.test(raw)) throw new Error("This link doesn't return an iCal calendar");
  const lines = raw.replace(/\r\n/g, "\n").replace(/\n[ \t]/g, "").split("\n");
  const events = [];
  let cur = null;
  for (const line of lines) {
    if (/^BEGIN:VEVENT/i.test(line)) cur = {};
    else if (/^END:VEVENT/i.test(line)) {
      if (cur?.start) {
        const end = cur.end && cur.end > cur.start ? cur.end : fmtDate(new Date(Date.parse(`${cur.start}T00:00:00Z`) + DAY));
        events.push({
          uid: cur.uid || `${cur.start}-${end}-${cur.summary ?? ""}`,
          start: cur.start,
          end,
          summary: cur.summary ?? "",
          description: cur.description ?? "",
          status: (cur.status ?? "CONFIRMED").toUpperCase(),
        });
      }
      cur = null;
    } else if (cur) {
      const i = line.indexOf(":");
      if (i < 0) continue;
      const name = line.slice(0, i).split(";")[0].toUpperCase();
      const value = line.slice(i + 1);
      if (name === "UID") cur.uid = value.trim();
      else if (name === "DTSTART") cur.start = toYmd(value);
      else if (name === "DTEND") cur.end = toYmd(value);
      else if (name === "SUMMARY") cur.summary = unescapeText(value).trim();
      else if (name === "DESCRIPTION") cur.description = unescapeText(value).trim().slice(0, 500);
      else if (name === "STATUS") cur.status = value.trim();
    }
  }
  return events;
}

/** Owner blocks on the OTA side ("Airbnb (Not available)", "CLOSED - Not available"). */
export const isBlockEvent = (e) => /not available|unavailable|closed|blocked/i.test(`${e.summary}`);

/** Builds an export calendar from closed date ranges [{start, end, summary, uid}]. */
export function buildIcs(name, ranges) {
  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const esc = (s) => String(s).replace(/([,;\\])/g, "\\$1").replace(/\n/g, "\\n");
  const out = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Bleiben//Channel Manager//EN", "CALSCALE:GREGORIAN", "METHOD:PUBLISH", `X-WR-CALNAME:${esc(name)}`];
  for (const r of ranges) {
    out.push(
      "BEGIN:VEVENT",
      `UID:${r.uid}`,
      `DTSTAMP:${stamp}`,
      `DTSTART;VALUE=DATE:${ymdToIcs(r.start)}`,
      `DTEND;VALUE=DATE:${ymdToIcs(r.end)}`,
      `SUMMARY:${esc(r.summary)}`,
      "END:VEVENT",
    );
  }
  out.push("END:VCALENDAR");
  return `${out.join("\r\n")}\r\n`;
}

/** Collapses per-night flags into contiguous [start, end) ranges. */
export function nightsToRanges(nights) {
  const out = [];
  for (const n of nights) {
    const last = out.at(-1);
    if (last && last.end === n) last.end = fmtDate(new Date(Date.parse(`${n}T00:00:00Z`) + DAY));
    else out.push({ start: n, end: fmtDate(new Date(Date.parse(`${n}T00:00:00Z`) + DAY)) });
  }
  return out;
}

function privateAddress(ip) {
  if (net.isIPv4(ip)) {
    const [a, b] = ip.split(".").map(Number);
    return a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127);
  }
  const v = ip.toLowerCase();
  return v === "::1" || v === "::" || v.startsWith("fc") || v.startsWith("fd") || v.startsWith("fe80") || v.startsWith("::ffff:127.") || v.startsWith("::ffff:10.") || v.startsWith("::ffff:192.168.");
}

/** Validates a feed URL (http/https, public host). Returns the normalised URL string. */
export async function checkFeedUrl(raw) {
  let u;
  try {
    u = new URL(String(raw ?? "").trim().replace(/^webcal:\/\//i, "https://"));
  } catch {
    throw new Error("Paste the full calendar link (it starts with https://)");
  }
  if (!["http:", "https:"].includes(u.protocol)) throw new Error("Calendar links must start with https://");
  if (!config.allowPrivateIcal) {
    const host = u.hostname.replace(/^\[|\]$/g, "");
    if (host === "localhost" || host.endsWith(".local") || host.endsWith(".internal")) throw new Error("That address isn't reachable from the internet");
    const ips = net.isIP(host) ? [host] : (await dns.lookup(host, { all: true }).catch(() => [])).map((r) => r.address);
    if (!ips.length) throw new Error("We couldn't find that website. Check the link.");
    if (ips.some(privateAddress)) throw new Error("That address isn't reachable from the internet");
  }
  return u.toString();
}

const MAX_BYTES = 5 * 1024 * 1024;

/** Downloads a feed with a timeout and size cap. */
export async function fetchFeed(url, fetchImpl = fetch) {
  const safe = await checkFeedUrl(url);
  const res = await fetchImpl(safe, { redirect: "follow", signal: AbortSignal.timeout(15000), headers: { "User-Agent": "Bleiben-Calendar-Sync/1.0" } });
  if (!res.ok) throw new Error(`The calendar link returned an error (${res.status})`);
  const text = await res.text();
  if (text.length > MAX_BYTES) throw new Error("That calendar is too large");
  return text;
}
