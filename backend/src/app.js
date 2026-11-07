import cors from "cors";
import express from "express";

import { config, corsOriginList } from "./config.js";
import { requireUser } from "./middleware/auth.js";
import { authRouter } from "./routes/auth.js";
import { staysRouter } from "./routes/stays.js";
import { publicUser } from "./security.js";

export function createApp(db) {
  const app = express();
  app.use(cors({ origin: corsOriginList() }));
  app.use(express.json());

  app.get("/api/health", (_req, res) => {
    res.json({ status: "ok", app: config.appName });
  });

  app.use("/api/auth", authRouter(db));
  app.get("/api/auth/me", requireUser(db), (req, res) => {
    res.json(publicUser(req.user));
  });
  app.use("/api/stays", requireUser(db), staysRouter(db));

  app.use((err, _req, res, _next) => {
    res.status(500).json({ detail: err.message || "Server error" });
  });

  return app;
}
