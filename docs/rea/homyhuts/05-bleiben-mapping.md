# 05 — Homeyhuts → Bleiben mapping

How each homyhuts feature lines up with the Bleiben PRD (R1 = MVP) and the
Development Plan sheet. Status as of 2026-11-11 on `main`.

| Bleiben module (sheet) | Owner | Homeyhuts reference | Bleiben status |
|---|---|---|---|
| Basic infra | Rahul | — | Done |
| Auth: OTP sign up / log in, email | Rahul | 03 · `/signup-signin` | **Done**: email OTP via Brevo; phone OTP needs an SMS provider |
| After-login behaviour | Rahul | 03 · stays on the homepage, avatar initial | **Done** |
| Account settings: personal info, photo, email/phone change, verification | Rahul | 03 · `/account/profile-info`, `/account/verification` | **Done** (no deactivate yet; ID verification "coming soon") |
| Organisation and roles (Owner, Manager, Staff, Read-only), invites | Rahul | 04 · Co-hosts and team | **Done** at org level. Per-property and per-feature levels: next |
| Property and unit management | Aman | 06 · listing wizard (19 steps, fields, enums) + 04 · Properties list (status filter, payment gateway column), Magic Cluster for units | To do |
| First-property setup | Aman (uses Rahul's auth) | 06 · start page (import / manual / clone), draft on step 1, resumable `current_step`, publish + setup call | To do. Open from "List your property" / "Start free trial", **never automatically** |
| Support tickets | — | 04 · Support panel (report issue / feedback / my tickets) | Later |
| Availability and calendar | — | 04 · Calendar (timeline, block/unblock, price per date, bulk %) | To do |
| Manual / walk-in / phone bookings | — | 04 · Reservations → Create Booking (offline) | To do |
| Overlap prevention and holds | — | Calendar + booking services | To do |
| Direct booking engine (hosted page, link, QR) | — | 02 · Direct booking website; reservations → booking requests approve/decline | To do |
| Payments (UPI/card advance via the owner's gateway) | later | 04 · Properties → payment gateway activation, payment links | Later |
| Two-way iCal sync | — | 04 · `property-calender-sync/*` | To do (R1) |
| Guest records | — | Reservations guest details | To do (R1) |
| Notifications / confirmations | — | (email, WhatsApp) | To do (R1) |
| Subscription billing | later | 03 · `/account/subscription-billings`, `host-it-yourself/*` | Later |
| Expenses, analytics, inbox, channel manager (OTA APIs) | — | 04 | Post-MVP |

## Conventions that follow from the REA

- Login never forces setup. Host tools open from explicit entry points.
- Every host screen carries an **access rule** (open / owner-only / feature),
  enforced on the server and mirrored in the UI.
- Domains stay separate (auth, property, booking, billing, channel, messaging),
  one router each in Bleiben.
- Bulk operations (prices, blocks, availability) are first-class: plan the API
  with `/bulk` variants from the start.
- Keep a change log per property (`property/logs`). Hosts and co-hosts expect "who changed what".
