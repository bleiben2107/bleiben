import { nowIso } from "./bookings/core.js";

/**
 * Activity log (Settings → Activity logs, MVP plan §2.9 "Audit logs").
 * Every successful change in an org-scoped module is recorded with who,
 * what and when. Reads are not logged.
 */

const RULES = [
  [/^POST \/api\/bookings$/, "Created a booking"],
  [/^PATCH \/api\/bookings\/\d+$/, "Edited a booking"],
  [/^POST \/api\/bookings\/\d+\/confirm$/, "Confirmed a booking"],
  [/^POST \/api\/bookings\/\d+\/cancel$/, "Cancelled a booking"],
  [/^POST \/api\/bookings\/\d+\/check-in$/, "Checked a guest in"],
  [/^POST \/api\/bookings\/\d+\/check-out$/, "Checked a guest out"],
  [/^POST \/api\/bookings\/\d+\/no-show$/, "Marked a no-show"],
  [/^POST \/api\/bookings\/\d+\/payments$/, "Recorded a payment"],
  [/^POST \/api\/calendar\/blocks$/, "Blocked dates"],
  [/^POST \/api\/calendar\/unblock$/, "Opened blocked dates"],
  [/^PATCH \/api\/calendar\/blocks$/, "Edited a block reason"],
  [/^PUT \/api\/calendar\/rates$/, "Changed prices"],
  [/^POST \/api\/properties$/, "Created a property"],
  [/^POST \/api\/properties\/\d+\/publish$/, "Published a property"],
  [/^POST \/api\/properties\/\d+\/unpublish$/, "Unpublished a property"],
  [/^POST \/api\/properties\/\d+\/rooms$/, "Added a room"],
  [/^(PATCH|PUT) \/api\/properties\/\d+\/rooms\/\d+$/, "Edited a room"],
  [/^DELETE \/api\/properties\/\d+\/rooms\/\d+$/, "Archived a room"],
  [/^POST \/api\/properties\/\d+\/photos$/, "Uploaded a property photo"],
  [/^(PATCH|PUT) \/api\/properties\/\d+$/, "Edited a property"],
  [/^DELETE \/api\/properties\/\d+$/, "Archived a property"],
  [/^POST \/api\/properties\/clone\/\d+$/, "Duplicated a property"],
  [/^POST \/api\/expenses$/, "Added an expense"],
  [/^PATCH \/api\/expenses\/\d+$/, "Edited an expense"],
  [/^DELETE \/api\/expenses\/\d+$/, "Deleted an expense"],
  [/^\w+ \/api\/expenses\/rules/, "Changed a repeating expense"],
  [/^POST \/api\/channels$/, "Connected a calendar"],
  [/^PATCH \/api\/channels\/\d+$/, "Edited a calendar connection"],
  [/^DELETE \/api\/channels\/\d+$/, "Disconnected a calendar"],
  [/^POST \/api\/channels\/\d+\/sync$/, "Synced a calendar"],
  [/^POST \/api\/channels\/conflicts\/\d+\/resolve$/, "Resolved a calendar conflict"],
  [/^POST \/api\/channels\/exports\/\d+\/regenerate$/, "Reset a calendar export link"],
  [/^PATCH \/api\/settings\/organization$/, "Updated organisation details"],
  [/^POST \/api\/settings\/organization\/logo$/, "Changed the logo"],
  [/^PATCH \/api\/settings\/preferences$/, "Changed property defaults"],
  [/^PATCH \/api\/settings\/notifications$/, "Changed notification settings"],
  [/^PUT \/api\/settings\/payment-gateway$/, "Changed the payment gateway"],
  [/^POST \/api\/billing\/checkout\/\d+\/verify$/, "Paid for the subscription"],
  [/^POST \/api\/billing\/cancel$/, "Cancelled the subscription"],
  [/^POST \/api\/billing\/resume$/, "Resumed the subscription"],
  [/^POST \/api\/messages\/\d+\/messages$/, "Sent or logged a message"],
];

const IGNORE = [/^POST \/api\/bookings\/quote$/, /^POST \/api\/billing\/(quote|checkout)$/, /^POST \/api\/messages\/\d+\/(state|render)$/, /^POST \/api\/expenses\/attachments$/, /^PUT \/api\/messages\/\d+\/note$/];

export function describe(method, path) {
  const key = `${method} ${path}`;
  if (IGNORE.some((r) => r.test(key))) return null;
  for (const [re, label] of RULES) if (re.test(key)) return label;
  return null;
}

/** Middleware: logs successful writes after the response is sent. */
export function auditTrail(db) {
  return (req, res, next) => {
    if (["GET", "HEAD", "OPTIONS"].includes(req.method)) return next();
    res.on("finish", () => {
      if (res.statusCode >= 400 || req.scope?.org_id == null) return;
      const path = req.originalUrl.split("?")[0].replace(/\/+$/, "");
      const action = describe(req.method, path);
      if (!action) return;
      db.insertDoc("audit_logs", {
        org_id: req.scope.org_id,
        user_id: req.user?.id ?? null,
        user_name: req.user?.name || req.user?.email || "",
        action,
        path,
        target_id: Number(path.match(/\/(\d+)(?:\/[a-z-]+)?$/)?.[1]) || null,
        ip: req.ip ?? null,
        at: nowIso(),
      }).catch((err) => console.error("[audit]", err.message));
    });
    return next();
  };
}
