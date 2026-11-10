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

  router.get("/", async (req, res, next) => {
    try {
      return res.json(await db.listStays(req.user.id));
    } catch (err) {
      return next(err);
    }
  });

  router.post("/", async (req, res, next) => {
    try {
      const payload = stayPayload(req.body);
      if (payload.error) {
        return res.status(400).json({ detail: payload.error });
      }
      return res.status(201).json(await db.createStay(req.user.id, payload));
    } catch (err) {
      return next(err);
    }
  });

  router.get("/:id", async (req, res, next) => {
    try {
      const stay = await db.findStay(Number(req.params.id), req.user.id);
      if (!stay) {
        return res.status(404).json({ detail: "Stay not found" });
      }
      return res.json(stay);
    } catch (err) {
      return next(err);
    }
  });

  router.patch("/:id", async (req, res, next) => {
    try {
      const stay = await db.findStay(Number(req.params.id), req.user.id);
      if (!stay) {
        return res.status(404).json({ detail: "Stay not found" });
      }
      return res.json(await db.updateStay(stay, stayPayload(req.body, { partial: true })));
    } catch (err) {
      return next(err);
    }
  });

  router.delete("/:id", async (req, res, next) => {
    try {
      const deleted = await db.deleteStay(Number(req.params.id), req.user.id);
      if (!deleted) {
        return res.status(404).json({ detail: "Stay not found" });
      }
      return res.status(204).end();
    } catch (err) {
      return next(err);
    }
  });

  return router;
}
