# Homeyhuts REA — reference for Bleiben

Reverse-engineering analysis (REA) of **homeyhuts.com**, the product Bleiben's
UI and flows are modelled on. Read this **before starting any new module or
screen**, so Bleiben follows the same flow instead of inventing one.

Captured: **2026-11-11**, using REA tools plus the public site, `robots.txt`,
`sitemap.xml` and the JavaScript bundles each app ships. Homeyhuts changes over
time, so re-check a screen live before copying fine detail.

## Files

| File | What's in it | Use it when |
|---|---|---|
| [01-architecture.md](01-architecture.md) | The apps (portal, host panel, admin), API microservices, auth and session, user types, third-party services | Designing the backend or auth |
| [02-public-site.md](02-public-site.md) | Marketing site: pages, nav, homepage sections, account menu, CTAs | Building or changing the public website |
| [03-auth-and-account.md](03-auth-and-account.md) | Sign up / log in (OTP), account settings, verification, payout details | Auth, profile, settings work (Rahul) |
| [04-host-panel.md](04-host-panel.md) | Host Control Center: screens, access rules, co-hosts/roles, what each screen does, its APIs | Any host-side module (Aman: properties, calendar, reservations…) |
| [06-property-listing-wizard.md](06-property-listing-wizard.md) | The full "list your property" flow, live: start-trial form, start page, all 19 steps with fields and options, AI assistant, publish | Property / unit setup (Aman), first-property onboarding |
| [05-bleiben-mapping.md](05-bleiben-mapping.md) | How the homyhuts features map to Bleiben's PRD/MVP, and what is built | Planning a task / checking scope |
| [raw/routes.txt](raw/routes.txt) | Every route in both apps, with access rules | Quick lookup |
| [raw/endpoints-guest-portal.txt](raw/endpoints-guest-portal.txt) | 69 API calls made by homeyhuts.com | API naming / shapes |
| [raw/endpoints-host-panel.txt](raw/endpoints-host-panel.txt) | 307 API paths used by host.homeyhuts.com, grouped by service | Designing a module's API |

## How to use it for a new task

1. Find the feature in **05-bleiben-mapping.md**: it tells you the homyhuts
   screen and the Bleiben owner.
2. Read that screen in **04-host-panel.md** (or 02/03) for flow, fields and access rules.
3. Look up its endpoints in `raw/` to name and shape Bleiben's API (Bleiben uses
   its own `/api/...` routes. Copy the *resource model*, not the URLs).
4. Follow Bleiben's conventions in [../../HANDOFF-AMAN.md](../../HANDOFF-AMAN.md):
   org scoping (`X-Org-Id` + `orgScope`), permissions in `roles.js`, and `{detail}` errors.
5. Build original Bleiben UI with Bleiben branding. Match the **structure and
   flow**, not Homeyhuts' copy, artwork or logos.

## Coverage and limits

- **Fully covered (static):** routes of both apps, API services and endpoints,
  the auth mechanism, user types, co-host access model, host-panel navigation
  and access rules, public page structure.
- **Covered live (logged in):**
  - Sign up / log in (email and phone OTP via SMS or WhatsApp), the account
    menu, Account settings (Personal info, Account Verifications).
  - `/start-trial`, the whole **property listing wizard** (all steps, read-only
    with a placeholder id; nothing saved).
  - The host panel as a new host sees it: top nav, channel-manager gate,
    Properties list and Magic Cluster, avatar menu, Support tickets, Refer &
    earn, My Account.
- **Still from code only:** dashboard, calendar, reservations, expenses, inbox
  and the property editor. They're locked until a channel manager is connected
  and a property exists. Capturing them needs a host account with a connected
  property: log in to homyhuts in the REA Chrome window
  (`--remote-debugging-port=9333`) and re-run.
- Nothing was created, submitted or changed on the homyhuts account during the REA.
- Admin-only endpoints (`/admin/…`) are bundled in the host panel but belong to
  Homeyhuts' internal tooling. They're listed in raw/ for completeness only.
- No personal data, tokens or credentials are recorded in these files.
