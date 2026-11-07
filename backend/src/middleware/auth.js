import { readAccessToken } from "../security.js";

export function requireUser(db) {
  return (req, res, next) => {
    const header = req.headers.authorization || "";
    const [scheme, token] = header.split(" ");
    if (scheme !== "Bearer" || !token) {
      return res.status(401).json({ detail: "Not authenticated" });
    }
    try {
      const userId = readAccessToken(token);
      const user = db.findUserById(userId);
      if (!user) {
        return res.status(401).json({ detail: "User not found" });
      }
      req.user = user;
      return next();
    } catch {
      return res.status(401).json({ detail: "Invalid token" });
    }
  };
}
