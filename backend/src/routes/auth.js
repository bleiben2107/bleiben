import { Router } from "express";

import { createAccessToken, hashPassword, publicUser, verifyPassword } from "../security.js";

export function authRouter(db) {
  const router = Router();

  router.post("/register", (req, res) => {
    const name = String(req.body?.name || "").trim();
    const email = String(req.body?.email || "").toLowerCase().trim();
    const password = String(req.body?.password || "");
    if (name.length < 2 || email.length < 5 || password.length < 6) {
      return res.status(400).json({ detail: "Name, email, and password are required" });
    }
    if (db.findUserByEmail(email)) {
      return res.status(409).json({ detail: "Email already registered" });
    }
    const user = db.createUser({ name, email, passwordHash: hashPassword(password) });
    return res.status(201).json({
      access_token: createAccessToken(user.id),
      token_type: "bearer",
      user: publicUser(user),
    });
  });

  router.post("/login", (req, res) => {
    const email = String(req.body?.email || "").toLowerCase().trim();
    const password = String(req.body?.password || "");
    const user = db.findUserByEmail(email);
    if (!user || !verifyPassword(password, user.password_hash)) {
      return res.status(401).json({ detail: "Invalid email or password" });
    }
    return res.json({
      access_token: createAccessToken(user.id),
      token_type: "bearer",
      user: publicUser(user),
    });
  });

  return router;
}
