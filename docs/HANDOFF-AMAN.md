# Handoff: where modules plug in (for Aman)

Rahul's part (auth, account settings, organisation + roles) is in place. Build
property/unit, calendar and booking modules on top of it like this.

**Before building a screen, read the Homeyhuts REA in
[docs/rea/homyhuts/](rea/homyhuts/README.md)**. It lists every host-panel
screen, its fields, access rules and APIs, and maps them to Bleiben modules.

## Backend (`backend/`)

- **Every request is signed in.** Mount routes behind `requireUser(db)`
  (`src/middleware/auth.js`). `req.user` is the signed-in user.
- **Every module is organisation-scoped.** The client sends `X-Org-Id`. Wrap the
  router in `src/app.js` like:
  `app.use("/api/properties", requireUser(db), orgScope(db, { read: "properties.read", write: "properties.write" }), propertiesRouter(db))`.
  Inside, `req.scope.org_id` and `req.membership` are set; store
  `org_id` on every document and always filter by it.
- **Permissions.** Add your module's permissions to each role in
  `src/roles.js` (`PERMISSIONS`), e.g. `properties.read` for all roles,
  `properties.write` for owner/manager/staff. Check extra actions with
  `requireOrgPermission(db, "<perm>")`.
- **Storage.** Use the generic store methods so JSON and MongoDB both work:
  `db.insertDoc / findDoc / findDocs / updateDoc / deleteDocs(collection, …)`.
- **Errors.** Respond `{ detail: "message" }` with a proper status code; the
  app shows `detail` as-is.
- **Photos.** `savePhoto(folder, { data: base64 })` in `src/uploads.js` returns
  a `/media/...` URL (JPG/PNG/WebP, ≤ 5 MB).
- **Tests.** Copy the helpers in `tests/auth.test.js` (`signUp`, `withServer`,
  fake mailer/SMS); a signed-up user is already Owner of their organisation.

## Frontend (`frontend/lib/`)

- `ApiClient` adds the token and `X-Org-Id` automatically.
- `auth.activeMembership` gives the current organisation, role and
  `can("<perm>")` — use it to hide buttons the role can't use (the server
  still enforces it).
- Entry points that are placeholders today and are yours to wire up:
  "List your property" / "Start free trial" (homepage + account menu,
  `features/home/home_screen.dart`) and "List Your Property" in the Account
  settings top bar (`features/account/account_screen.dart`).

## Not built yet

Property setup / units / photos / pricing, calendar, booking engine, payments
(later), government-ID verification, account deactivation.
