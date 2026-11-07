import { Router } from "express";

function stayPayload(body, { partial = false } = {}) {
  const title = body?.title;
  const location = body?.location;
  if (!partial && (!title || !location)) {
    return { error: "Title and location are required" };
  }
  return {
    title,
    location,
    notes: body?.notes,
    check_in: body?.check_in,
    check_out: body?.check_out,
  };
}

export function staysRouter(db) {
  const router = Router();

  router.get("/", (req, res) => {
    res.json(db.listStays(req.user.id));
  });

  router.post("/", (req, res) => {
    const payload = stayPayload(req.body);
    if (payload.error) {
      return res.status(400).json({ detail: payload.error });
    }
    return res.status(201).json(db.createStay(req.user.id, payload));
  });

  router.get("/:id", (req, res) => {
    const stay = db.findStay(Number(req.params.id), req.user.id);
    if (!stay) {
      return res.status(404).json({ detail: "Stay not found" });
    }
    return res.json(stay);
  });

  router.patch("/:id", (req, res) => {
    const stay = db.findStay(Number(req.params.id), req.user.id);
    if (!stay) {
      return res.status(404).json({ detail: "Stay not found" });
    }
    return res.json(db.updateStay(stay, stayPayload(req.body, { partial: true })));
  });

  router.delete("/:id", (req, res) => {
    const deleted = db.deleteStay(Number(req.params.id), req.user.id);
    if (!deleted) {
      return res.status(404).json({ detail: "Stay not found" });
    }
    return res.status(204).end();
  });

  return router;
}
