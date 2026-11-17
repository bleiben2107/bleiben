import cors from "cors";
import express from "express";

import { config, corsOriginList } from "./config.js";
import { EmailDeliveryError, createMailer, createSmsSender } from "./messaging.js";
import { requireUser, orgScope } from "./middleware/auth.js";
import { accountRouter } from "./routes/account.js";
import { authRouter } from "./routes/auth.js";
import { invitesRouter, orgsRouter } from "./routes/orgs.js";
import { bookingsRouter } from "./routes/bookings.js";
import { calendarRouter } from "./routes/calendar.js";
import { dashboardRouter } from "./routes/dashboard.js";
import { expensesRouter } from "./routes/expenses.js";
import { messagesRouter } from "./routes/messages.js";
import { propertiesRouter } from "./routes/properties.js";
import { auditTrail } from "./audit.js";
import { requireFeature, requireWritable } from "./billing/subscription.js";
import { billingRouter } from "./routes/billing.js";
import { channelsRouter, icalExportRouter } from "./routes/channels.js";
import { notificationsRouter } from "./routes/notifications.js";
import { publicRouter } from "./routes/public.js";
import { settingsRouter } from "./routes/settings.js";
import { publicUser } from "./security.js";
import { uploadsDir } from "./uploads.js";
import { membershipsFor } from "./session.js";

/**
 * @param db store from createDb/createMongoDb
 * @param services optional overrides (tests pass fake mailer/sms)
 */
export function createApp(db, services = {}) {
  const mailer = services.mailer ?? createMailer();
  const sms = services.sms ?? createSmsSender();
  // Shared with modules that send notifications / call gateways (tests inject fakes).
  const svc = { mailer, sms, fetch: services.fetch };

  const app = express();
  app.use(cors({ origin: corsOriginList(), allowedHeaders: ["Content-Type", "Authorization", "X-Org-Id"] }));
  // Profile photos arrive as base64 JSON (up to 5 MB); everything else is small.
  app.use("/api/account/avatar", express.json({ limit: "8mb" }));
  app.use("/api/expenses/attachments", express.json({ limit: "8mb" }));
  app.use("/api/settings/organization/logo", express.json({ limit: "8mb" }));
  app.use(/^\/api\/properties\/\d+\/photos$/, express.json({ limit: "8mb" }));
  // Razorpay webhooks are verified against the raw body.
  app.use("/api/public/payments/razorpay", express.raw({ type: "*/*", limit: "1mb" }));
  app.use(express.json({ limit: "100kb" }));
  // Uploaded photos (unguessable file names), cached for a day.
  app.use("/media", express.static(uploadsDir, { maxAge: "1d", fallthrough: false, index: false }));

  app.get("/api/health", async (_req, res, next) => {
    try {
      await db.ping?.();
      return res.json({
        status: "ok",
        app: config.appName,
        db: db.kind || "json",
        email: mailer.configured ? "smtp" : "console",
        sms: sms.configured ? "provider" : "console",
      });
    } catch (err) {
      return next(err);
    }
  });

  app.use("/api/auth", authRouter(db, { mailer, sms }));
  app.get("/api/auth/me", requireUser(db), async (req, res, next) => {
    try {
      return res.json({ ...publicUser(req.user), memberships: await membershipsFor(db, req.user.id) });
    } catch (err) {
      return next(err);
    }
  });
  app.use("/api/account", requireUser(db), accountRouter(db, { mailer, sms }));
  app.use("/api/orgs", requireUser(db), orgsRouter(db, { mailer }));
  app.use("/api/invites", requireUser(db), invitesRouter(db));

  // Public: guest booking page + checkout, and iCal export links.
  app.use("/api/public", publicRouter(db, svc));
  app.use("/api/ical", icalExportRouter(db));

  // Org-scoped module routes: permission check → subscription read-only guard → activity log.
  const mod = (path, perms, router, ...extra) =>
    app.use(path, requireUser(db), orgScope(db, perms), ...extra, auditTrail(db), router);
  const writable = requireWritable(db);
  mod("/api/properties", { read: "properties.read", write: "properties.write" }, propertiesRouter(db), writable);
  mod("/api/calendar", { read: "calendar.read", write: "calendar.write" }, calendarRouter(db), writable);
  mod("/api/bookings", { read: "bookings.read", write: "bookings.write" }, bookingsRouter(db, svc), writable);
  mod("/api/expenses", { read: "expenses.read", write: "expenses.write" }, expensesRouter(db), requireFeature(db, "expenses"), writable);
  mod("/api/dashboard", { read: "dashboard.read", write: "dashboard.read" }, dashboardRouter(db));
  mod("/api/messages", { read: "messages.read", write: "messages.write" }, messagesRouter(db), requireFeature(db, "inbox"), writable);
  mod("/api/channels", { read: "channels.read", write: "channels.write" }, channelsRouter(db, svc), writable);
  mod("/api/notifications", { read: "notifications.read", write: "notifications.read" }, notificationsRouter(db));
  mod("/api/settings", { read: "org.read", write: "org.read" }, settingsRouter(db, svc), writable);
  mod("/api/billing", { read: "org.read", write: "org.read" }, billingRouter(db, svc));

  app.use((err, _req, res, _next) => {
    if (err instanceof EmailDeliveryError) {
      return res.status(502).json({ detail: err.message });
    }
    console.error(err);
    res.status(500).json({ detail: config.isProduction ? "Server error" : err.message || "Server error" });
  });

  return app;
}
