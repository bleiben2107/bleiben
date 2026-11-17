import { Router } from "express";

import { InputError } from "../bookings/core.js";
import { NOTIFICATION_KINDS } from "../notify.js";

/** /api/notifications — Inbox → Notifications (MVP plan §2.6 R1). Read state is per user. */

const handle = (fn) => async (req, res, next) => {
  try {
    if (req.scope?.org_id == null) throw new InputError("Choose an organisation (X-Org-Id) first");
    return await fn(req, res);
  } catch (err) {
    if (err instanceof InputError) return res.status(err.status).json({ detail: err.message, ...err.extra });
    return next(err);
  }
};

function view(n, userId) {
  return {
    id: n.id,
    kind: n.kind,
    kind_label: NOTIFICATION_KINDS[n.kind] ?? n.kind,
    title: n.title,
    body: n.body,
    booking_id: n.booking_id,
    booking_code: n.booking_code,
    data: n.data ?? {},
    deliveries: n.deliveries ?? [],
    muted: !!n.muted,
    read: (n.read_by ?? []).includes(userId),
    created_at: n.created_at,
  };
}

export function notificationsRouter(db) {
  const router = Router();

  const mine = async (req) => (await db.findDocs("notifications", { org_id: req.scope.org_id })).sort((a, b) => b.id - a.id);

  router.get("/", handle(async (req, res) => {
    let list = await mine(req);
    if (req.query.kind && req.query.kind !== "all") list = list.filter((n) => n.kind === req.query.kind);
    if (req.query.unread === "true") list = list.filter((n) => !(n.read_by ?? []).includes(req.user.id));
    if (req.query.failed === "true") list = list.filter((n) => (n.deliveries ?? []).some((d) => d.status === "failed"));
    const page = Math.max(1, Number(req.query.page) || 1);
    const size = Math.min(100, Number(req.query.page_size) || 30);
    return res.json({ items: list.slice((page - 1) * size, page * size).map((n) => view(n, req.user.id)), total: list.length, page, page_size: size, kinds: NOTIFICATION_KINDS });
  }));

  router.get("/unread-count", handle(async (req, res) => {
    const list = await mine(req);
    return res.json({ count: list.filter((n) => !(n.read_by ?? []).includes(req.user.id)).length });
  }));

  router.get("/:id", handle(async (req, res) => {
    const n = await db.findDoc("notifications", { id: Number(req.params.id) });
    if (!n || n.org_id !== req.scope.org_id) throw new InputError("Notification not found", 404);
    return res.json(view(n, req.user.id));
  }));

  // Marking read is personal; allowed for read-only members too (POST under read permission).
  router.post("/:id/read", handle(async (req, res) => {
    const n = await db.findDoc("notifications", { id: Number(req.params.id) });
    if (!n || n.org_id !== req.scope.org_id) throw new InputError("Notification not found", 404);
    const read = new Set(n.read_by ?? []);
    if (req.body?.read === false) read.delete(req.user.id);
    else read.add(req.user.id);
    await db.updateDoc("notifications", { id: n.id }, { read_by: [...read] });
    return res.json({ read: read.has(req.user.id) });
  }));

  router.post("/read-all", handle(async (req, res) => {
    let n = 0;
    for (const x of await mine(req)) {
      if ((x.read_by ?? []).includes(req.user.id)) continue;
      await db.updateDoc("notifications", { id: x.id }, { read_by: [...(x.read_by ?? []), req.user.id] });
      n += 1;
    }
    return res.json({ marked: n });
  }));

  return router;
}
