# 04 — Host Control Center (host.homeyhuts.com)

The logged-in workspace for hosts. This is the reference for **every host
module Bleiben builds next** (properties, calendar, reservations, expenses,
inbox, channels). Screen descriptions come from the shipped bundle: route
table, access rules, UI labels per lazy-loaded screen, and API calls. Items
marked *(inferred)* weren't seen live. The live capture section below covers
what a new host account sees; screens behind the channel-manager gate
(dashboard, calendar, reservations, expenses, inbox) are still from code.

## Getting there

- Portal account menu → "Host Control Center", or "Start free trial" / "List your property":
  - an `HHHost` goes to `host.homeyhuts.com/listing`;
  - a new user first goes through `/host-your-property/add-property` on the portal.
- Login: the host panel has its own `/login` ("Welcome to Homeyhuts · Host
  Portal", one *Email / Phone Number* field). It shares the `passcode` cookie
  with the portal.
- **First-property setup** (portal, `/host-your-property/add-property`), seen live:
  - Three stages: **Add your property → Complete your listing → Connect your OTAs**.
  - Three ways to start: **import from Airbnb** (`/clone/airbnb`), **create
    manually**, or **clone an existing property** (`property/copy-exiting-property/{id}?title=`).
  - "Create manually" creates a draft (`POST /property/api/v1/property`) and then walks through **19 step pages**.
  - Full step-by-step detail: [06-property-listing-wizard.md](06-property-listing-wizard.md).

## Live capture (logged in, 2026-11-11)

Captured on a new host account with no properties and no channel manager.

- **Top nav** (horizontal, not a sidebar): logo · Dashboard · Calendar ·
  **Properties** · Reservations · Expenses · Inbox · **Support** · 🎁 (Refer &
  earn) · ▶ (YouTube tutorials) · avatar initial + ☰.
- **Channel-manager gate (seen live):**
  - A banner reads "Connect your channel manager to unlock all tabs — only
    Properties is available until a channel manager is connected", with
    **Connect channel manager** and a *Contact support* mailto.
  - The other tabs show a 🔒 icon, and opening any of their routes
    (`/dashboard`, `/calendar`, `/reservations`, `/expenses`, `/inbox`,
    `/channel-manager`) **redirects to `/listing`**.
  - Bleiben lesson: gate premium screens by plan/state, and say why.
- **Properties → All Properties:**
  - Search (name / id / city), Status filter (All, Activated, Deactivated, Declined, Draft).
  - **Create New Listing** goes to the portal wizard ([06-property-listing-wizard.md](06-property-listing-wizard.md)).
  - Table columns: Id, Title, City, Status, **Payment Gateway** (per-row toggle,
    "All" checkbox, and a "turned on/off — click Save to confirm" dialog). Empty state: "No data".
- **Properties → Magic Cluster:** search by name, **New Cluster**; table:
  Cluster Name, Cluster Id, Mapping, Entire Place Mode, Action.
- **Avatar menu (host panel):** Create New Listing, Host Control Center, Home,
  About Us, Trips, Account Settings, Contact Us, Help Center, Travel Blogs, Host
  Knowledge Hub, State Regulation, Hosting Templates, Logout.
- **Support** (side panel):
  - Tabs: **Report an issue** / **Feedback** / **My tickets (n)**.
  - Form: Property \*, Category \* (Unified Calendar, Unified Inbox, Expenses,
    Property Calendar, Reservations, Pricing, Direct Booking website,
    Reporting & Dashboard, Others), description \* (≤ 1000), up to 2
    attachments (5 MB each, JPG/PNG/PDF), **Raise ticket**.
  - Email confirmation when a ticket opens and closes (`cms/api/v1/support`).
- **Refer & earn** (🎁): a fixed cash reward per referred host who makes a first
  payment, a personal link (`homeyhuts.com/r/<code>`) with Copy and *Send on
  WhatsApp*, and a wallet ("Nothing in your wallet yet").
- **My Account** (`/account`, tabs Profile · Verification · Payout Details): the
  tabs render empty placeholders on this account. The working Account settings
  are on the portal (`homeyhuts.com/account/profile-info`, see 03).
  `/account/subscription-billings` shows "Page Not Found!" for this account.

## Navigation and access

Nav order: **Dashboard · Calendar · Properties · Reservations · Expenses ·
Inbox** (plus Channel Manager for owners), with Support, referral and the account
in the header. Each route declares an access rule:

| Route | Nav label | Access |
|---|---|---|
| `/dashboard` | Dashboard | feature `dashboard` |
| `/calendar` | Calendar | feature `calendar` |
| `/listing`, `/listing/properties/:id` | Properties | feature `property` |
| `/listing/cluster/:id[/entire-place-mode]` | Magic Cluster | owner only |
| `/reservations` | Reservations | feature `reservation` |
| `/expenses` | Expenses | feature `expense` |
| `/inbox[/:threadId]` | Inbox | feature `MESSAGE_INBOX` |
| `/channel-manager` | Channel Manager | owner only |
| `/account`, `/account/subscription-billings` | Account | open |

Rule, as in the code:
- `open` is always allowed.
- `ownerOnly` needs `isAccountOwner`.
- `feature` needs the member's **best level** for that feature to be anything
  other than `noAccess`.

While permissions load, the screen waits. If the screen isn't allowed, the
user is redirected to the first allowed screen in the co-host's feature
`displayOrder`, or sees a "no access" page.

Subscription gate: a `SUBSCRIPTION` host with **no paid plan and no connected
channels** is limited to `listing/*` and `account` until they connect.

## Co-hosts and team (roles) — Rahul's area

| Concept | Value |
|---|---|
| Member kinds | **Account owner**; **account manager** (whole account); **co-host** (chosen properties) |
| Features | `dashboard`, `calendar`, `reservation`, `property`, `expense`, `MESSAGE_INBOX` |
| Levels per feature | `noAccess` (0) < `readOnly` (1) < `fullAccess` (2) |
| Invite status | `pending` → `active`, or `revoked` |
| Limit | Up to **10** co-hosts per property *(constant in code, inferred meaning)* |
| Invite flow | Owner invites by email per property (`POST auth/api/v1/co-host/property/{propertyId}/invite`; resend: `…/{id}/resend`). The invitee opens `/co-host/invite/:token` and sees a preview ("Join as a Co-Host", "Signed in as …"). Error cases: "This invite has expired", "This invite is for a different email". Then they sign in (OTP), "Accept invite" (`POST auth/api/v1/co-host/accept`), "Start Co-hosting". |
| APIs | `GET co-host/features`, `GET co-host/property/{propertyId}` (list), `PATCH/DELETE co-host/property/{propertyId}/{coHostId}` *(inferred methods)* |

Bleiben today has organisation-level roles (Owner / Manager / Staff / Read-only)
and email invites (Account settings → Team & roles). The next step to match
homyhuts is **per-property assignment** and **per-feature levels**. Keep that in
mind when adding `properties.*`, `calendar.*`, `bookings.*` permissions.

## Screens

### Dashboard (`/dashboard`)
- KPIs: net revenue, net operating income, nights booked, occupancy, **Net
  ADR**, **Net RevPAR**, bookings / cancelled.
- "Revenue and expenses" monthly chart (hover for figures); performance table
  ("Rank properties by"); "Occupancy outlook"; sources by channel.
- Today panels: check-ins, check-outs, ongoing stays.
- Filters: all properties / single vs multi listings, location, custom date range.
- Quick actions: **Add direct booking**, **Add expenses**.
- APIs: `booking/host-dashboard`, `booking/host-dashboard-info`,
  `booking/day-wise-count`, `booking/total-earning`, `booking/recents`, `property/property/property-occupancy-list`.

### Calendar (`/calendar`)
- Multi-property timeline: bookings from every channel plus blocked dates.
- Per-date **price** and **availability**.
- **Block / unblock** dates with a reason and notes (bulk, overwrite notes). Block history is kept.
- **Flexi Pricing** (bulk %):
  - Pick listings, filtered by location and **occupancy** (greater / less than / between, over a window).
  - Pick a date range and weekdays ("Apply on these days").
  - Increase or decrease by %, or set a price.
- **Entire Place Mode** for clusters.
- Plan-type filter: Subscription / Pay Per Booking / HH Managed / Full Service.
- APIs:
  - `property/unified-cal-property-list`, `property/all-property-price`, `property/all-property-blocks`.
  - `property-manage-price` (and `/bulk-update`, `/by-percentage`).
  - `property-block-date` (and `/bulk`, `/bulk/delete`, `/block-date-reasons`, `/block-history/*`, `/full-sync/{id}`).

### Properties (`/listing`, `/listing/properties/:id`)
- List: search by name / id / city, status, "Create New Listing", Magic Cluster
  tab (cluster name, listings in cluster, mapping, new cluster).
- **Payment gateway activation** flow (per property):
  - Explainer sections: how it works, fees & settlement, settlement delays, refunds.
  - The host reads and accepts an agreement, then "Review and activate".
  - APIs: `property-user-agreement`, `property-payment-gateway/bulk`.
- **Property editor** sections:
  - Property Info / Type / Category, Address and Neighbourhood, **Guests &
    Rooms** (guests included, price per extra guest), Amenities, Experiences offered.
  - **Property Photos**, **Property Documents** (KYC / verification).
  - Pricing Settings, **Discounts / Discount rules**, Tax / **GST** (number, trade/company name).
  - Check-in / check-out times and **Check-in Method**, **House rules**, Guest
    permissions / controls, **Cancellation policy** (policy & refunds).
  - Co-hosts (per property), Property Calendar.
- APIs:
  - `property/{id}`, `property/manage-property`, `property-settings`, `property-address`, `property-amenities`.
  - `property-files/*`, `property-addon-service`, `property/gst-settings`.
  - `property/settings-comparison/{serialId}`, `property/logs/{id}` (change log).
  - Clusters: `create-property-cluster`, `get-property-cluster`.

### Reservations (`/reservations`)
- Tabs / status filter:
  - Arriving soon, checking in, checking out, upcoming, completed, cancelled.
  - **Booking requests** (direct-website requests: approve / decline).
  - **Booking leads**.
- Table: booking ID, guest, check-in/out, guests, platform (Airbnb,
  Booking.com, MakeMyTrip/Goibibo, Direct…), booking amount, guest paid,
  expected payout, status.
- Booking details drawer: transactions, adjustments, invoice (PDF).
- **Create Booking** (manual / offline):
  - Prefill per property (`manual-booking-prefill/{propertyId}`).
  - `create-direct-offline-booking`, record an offline payment, "mark balance received".
- Other APIs: `booking/reservations/list`, `/reservations/summary`,
  `booking-status-count`, `transactions/{id}`, `cancel-booking-info/{id}`,
  `host-booking-excel` (export), `invoices/list`, `payment-link`.

### Expenses (`/expenses`)
- List with filters: property, category, amount range, attachments, month; sort; export to Excel.
- Add / edit expense: date, property, category, amount, payment mode, attachments.
- **Monthly recurring** rules: schedule, skip a month (with reason), stop from today.
- "Auto-filed" items, and locking ("Expenses are locked").
- API: `property/api/v1/property-expense`.

### Inbox (`/inbox/:threadId`)
- Conversations across channels; filters by channel, listing, trip stage, agent, unread.
- "Waiting on you, most urgent first"; **reply-time** stats (typical / average, by agent).
- Thread actions: notes, star, priority, archive, read/unread, quick replies,
  scheduled messages, reviews, availability and property info side panel.
- APIs: `messaging/api/v1/threads/*`, `/reply-times`, `/attachments`. Live updates come over socket.io.
- Access is gated by plan (`host-it-yourself/inbox-access`, `inbox-plan-upgrade`).

### Channel Manager (`/channel-manager`, owner only)
- Connected channels per property, **rates and inventory** grid, bulk update
  (price / inventory / rate, increase or decrease by), filters by occupancy or service type.
- Full sync with sync logs, live feed of channel events, channel price / booking / availability rules.
- APIs: `channel-manager-x/api/v1/*` (`get-rate-inventory`, `create-bulk-rate`,
  `create-bulk-availability`, `full-sync-channel`, `live-feed`, …).
- iCal-style sync for other OTAs: `property-calender-sync/*`.

### Account (`/account`)
Covered in [03-auth-and-account.md](03-auth-and-account.md): profile,
verification, payout details, subscription billing.
