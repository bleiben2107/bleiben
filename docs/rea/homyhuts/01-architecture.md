# 01 — Architecture

## Three front-end apps, one API gateway

| App | URL | Stack | Who uses it |
|---|---|---|---|
| Guest + marketing portal | `https://homeyhuts.com` | Next.js (App Router, Turbopack chunks), React Query, axios, Tailwind/shadcn (`Sheet`, …) | Visitors, guests, hosts signing up; account settings |
| Host Control Center | `https://host.homeyhuts.com` | Vite + React SPA, React Router, Ant Design menus, React Query, axios, socket.io (`/engine.io`) | Hosts, property owners, co-hosts |
| Admin | `https://admin.homeyhuts.com` | (not analysed) | Homeyhuts staff |

All three call **`https://api.homeyhuts.com`**, which routes by path prefix to
separate services:

| Service prefix | Responsibility |
|---|---|
| `/auth/api/v1` | Users, OTP login, profile, email/phone change, verification (Aadhaar/ID), co-hosts, admin users, masters (country/state), message templates, devices (push) |
| `/property/api/v1` | Properties, address, amenities, photos/files, prices (`property-manage-price`, bulk, by-percentage), blocked dates, iCal/calendar sync, clusters, settings, expenses, booking leads, search (guest side) |
| `/booking/api/v1` | Bookings (OTA, direct, offline), reservations list/summary, dashboard numbers, earnings/statements, payouts, invoices, payment links, promo codes, direct-website booking requests, analytics events |
| `/host-it-yourself/api/v1` | Host subscription: plan type, default plan, dues, pay due/all dues, billing banner, referral, inbox access/upgrade, trial sign-ups |
| `/channel-manager-x/api/v1` | Channel manager v2: connected channels, rates/availability (single + bulk), restrictions, room types, rate plans, full sync, live feed |
| `/channel-manager-new/api/v1` | Channel manager provider settings (property managers, channel codes, sync logs) |
| `/messaging/api/v1` | Unified inbox: threads, messages, notes, star/priority/archive, quick replies, scheduled messages, reviews |
| `/cms/api/v1` | CMS: pages, articles, help videos by screen, homepage offer/header/destinations, WhatsApp support links |
| `/files/api/v1` | File upload (`upload-files-with-size-formatter`, multipart) |
| `/campaign/api/v1` | Contact / demo forms |
| `/schedule/api/v1` | Scheduled jobs (listing reminders) |
| `/travel-agent/api/v1` | B2B travel-agent calendar and verification |

**Takeaway for Bleiben:** split by domain the same way: auth, property,
booking, billing, channel and messaging. Bleiben runs this as one Express app
with one router per domain (`/api/auth`, `/api/account`, `/api/orgs`, …, and
next `/api/properties`, `/api/bookings`, …).

## Auth and session

- **Token:** a JWT-like *passcode*, stored in a **cookie named `passcode`** on
  the parent domain, so both `homeyhuts.com` and `host.homeyhuts.com` share it.
- **Request header:** every axios call sends `authentication: <passcode>`
  (custom header, not `Authorization: Bearer`). The portal also sends `X-Frontend-URL: <pathname>`.
- **Login hand-off to the host panel:** the host panel accepts `?passcode=` or
  `?token=` once, stores it in the cookie and removes it from the URL.
- **401 handling:**
  - On the host panel, a 401 sends the user to `https://homeyhuts.com/signup-signin?hostpanel=https://host.homeyhuts.com/`.
  - On the portal, a 401 clears the cookie and goes to `/login`.
  - Calls can opt out with `skipAuthRedirect`, e.g. a co-host invite preview.
- **Redirect after login:** a `redirect` cookie plus `?redirectUrl=` on `/signup-signin`.
- Axios defaults: base URL `https://api.homeyhuts.com`, 30 s timeout, `Accept: application/json`.

Bleiben equivalent: JWT bearer token in `Authorization`, stored in
SharedPreferences; 401 clears the session (see `frontend/lib/core/network/api_client.dart`).

## User types (`userSubType.code`)

| Code | Meaning |
|---|---|
| `guest` | Traveller account (default at sign-up) |
| `HHHost` | Host on a Homeyhuts subscription ("host it yourself") |
| `property_owner` | Owner whose property Homeyhuts manages |
| `co_host` | Invited team member with per-feature access |
| `account_manager` | Team member with whole-account access (vs co-host = chosen properties) |
| `travelAgent` | B2B travel agent |
| `admin`, `ADMIN_HHOST`, `customer_support` | Homeyhuts staff |

Higher-level `userType`: `admin` / `guest` / `host`.
Verification state: `pending` → `submitted` → `verified`.

Routing by type: on the portal, "Start free trial" sends an `HHHost` to
`host.homeyhuts.com/listing` and opens a dialog for a `property_owner`. Anyone
else starts the host registration funnel.

## Third-party services seen

| Service | Use |
|---|---|
| PostHog, Google Analytics 4 / GTM, Microsoft Clarity, Meta Pixel + Conversions API (server-side via `/booking/api/v1/analytics/event`) | Analytics, funnels, ads attribution (consent-gated) |
| Sentry | Error tracking |
| Mapbox GL, Google Maps | Maps on search / property pages |
| AWS S3 (`homeyhuts-assets.s3.ap-south-1`) | Images and assets |
| Razorpay | Guest payments (`/razorpay-payment`) and host subscription dues |
| YouTube (nocookie) | Help / demo videos |
| socket.io | Live updates in the host panel (inbox, live feed) |
| App Store / Play Store | Native host app (ID verification is done in the app) |
