import cors from "cors";
import express from "express";

import { config, corsOriginList } from "./config.js";
import { EmailDeliveryError, createMailer, createSmsSender } from "./messaging.js";
import { requireUser, orgScope } from "./middleware/auth.js";
import { accountRouter } from "./routes/account.js";
import { authRouter } from "./routes/auth.js";
import { invitesRouter, orgsRouter } from "./routes/orgs.js";
import { propertiesRouter } from "./routes/properties.js";
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

  const app = express();
  app.use(cors({ origin: corsOriginList(), allowedHeaders: ["Content-Type", "Authorization", "X-Org-Id"] }));
  // Profile photos arrive as base64 JSON (up to 5 MB); everything else is small.
  app.use("/api/account/avatar", express.json({ limit: "8mb" }));
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
  app.use(
    "/api/properties",
    requireUser(db),
    orgScope(db, { read: "properties.read", write: "properties.write" }),
    propertiesRouter(db)
  );
  app.use((err, _req, res, _next) => {
    if (err instanceof EmailDeliveryError) {
      return res.status(502).json({ detail: err.message });
    }
    console.error(err);
    res.status(500).json({ detail: config.isProduction ? "Server error" : err.message || "Server error" });
  });

  return app;
}
