# 02 — Public site (homeyhuts.com)

Bleiben's homepage (`frontend/lib/features/home/`) already mirrors this
structure. Use this file when adding pages or changing navigation.

## Global chrome

- **Offer bar** (top, dismissible): offer name, discount, "new hosts only",
  countdown (days / hrs / min) and a "Claim offer" button. Content comes from
  the CMS (`GET /cms/api/v1/home-page/offer`).
- **Nav bar:** logo · **Product ▾** · **Solutions ▾** · **Resources ▾** ·
  **Pricing** · **Reviews** · **Start free trial** (primary button) · **account button**.
  - The account button is an outlined pill with an avatar and a ☰ icon. Signed
    out, the avatar is a generic person icon; signed in, it shows the first initial ("R").
  - On narrow screens the nav becomes a drawer, with "Log in" plus ☰.
- **Account menu** (sheet sliding in from the right):
  - Signed out: header "Hey there!", **Sign up / Sign in** (highlighted), Book
    your stay, List your property, About us, Contact us, Help centre.
  - Signed in: header avatar + first name, Book your stay, List Your Property,
    About Us, Trips, Account Settings, Contact Us, Help Center, then **Logout**.
- **Floating buttons:** "Book a Demo" and "Book your stay" (bottom right), plus back-to-top.
- **Footer:**
  - Blurb and social links (Instagram, Facebook, Twitter/X, YouTube, LinkedIn).
  - Columns: COMPANY, FOR HOSTS, HELP & RESOURCES.
  - "Popular Locations" (state/city stay pages) and copyright.

## Nav menus

| Menu | Entries (page) |
|---|---|
| Product | Channel Manager, Unified Calendar, Direct Booking Website, Unified Inbox, Flexi Pricing, Offline Bookings, Magic Cluster, Expenses & Profits, Analytics, Co-hosts & Team |
| Solutions | Individual hosts, Property managers, Enterprise (200+ properties), New to hosting |
| Resources | Host Knowledge Hub / help, blog, articles (guides, templates, state regulations) |

## Homepage sections (in order)

1. Hero: rating badge ("4.9 · trusted by N properties"), headline, sub-text,
   channel icons ("syncs with 50+ channels"), Start free trial / Talk to our
   expert, and an animated product mockup (WhatsApp enquiry → offline booking → payment link).
2. Feature tiles (channel manager, offline booking, direct website, …).
3. Unified calendar showcase with a tabbed explainer.
4. Before / after ("hosting the hard way" vs "on autopilot") with stats.
5. "Everything you need": tabbed feature list.
6. Reach: more channels means more bookings.
7. Scale: one property or a thousand (plans by size).
8. Pricing: transparent, no commission. Monthly/annual toggle, plan cards.
9. Support promise: onboarding, knowledge hub, 1-on-1 support, migration, training.
10. Why us, then awards and recognition.
11. Reviews (video stories).
12. FAQ (about 18 questions, accordion).
13. Guides carousel (Host Knowledge Hub), final CTA, footer.

## Feature pages: common template

Every Product page (`/channel-manager`, `/unified-calendar`, `/flexi-pricing`,
`/offline-bookings`, `/magic-cluster`, `/expenses-and-profits`, `/analytics`,
`/co-hosts-and-team`, `/direct-booking-website`, `/unified-inbox`) follows the same outline:

1. Hero: the promise in one line.
2. The pain ("updating prices one by one").
3. Three to six capability blocks.
4. "Live / started in 3 steps".
5. Testimonials.
6. FAQ, then a final CTA.

What each page promises, i.e. the product scope:

| Page | Capabilities promised |
|---|---|
| Channel manager | Connect 50+ OTAs, update prices once, one calendar, shared inbox, no double bookings (vs iCal) |
| Unified calendar | All channels' bookings colour-coded on one timeline; block dates; bulk price edits |
| Direct booking website | Own domain, templates, 1 / 2–10 / 10+ property layouts, online payments direct to host, synced calendar, SEO, reviews, repeat guests |
| Unified inbox | All OTA + WhatsApp guest messages in one place, quick replies, scheduled messages |
| Flexi pricing | Bulk % up/down across properties, filter by occupancy/location, pick dates and weekdays, minimum-price guard, change history, syncs to every OTA |
| Offline bookings | Walk-in / phone / WhatsApp / Instagram bookings, payment link, prevents overlaps |
| Magic cluster | Group identical units / rooms so one listing sells many units |
| Expenses & profits | Expense entry (recurring), P&L per property, net operating income, AI insights |
| Analytics | Net revenue, NOI, occupancy, ADR, RevPAR, direct-booking share, compare properties/channels, Excel export |
| Co-hosts & team | Invite by email, whole-account (account manager) or chosen properties (co-host), per-feature permissions, hide financials, activity log |

## Guest side (for later)

`/stays` → `/search/{place}/homes` (filters, map, recent searches) →
`/property/{slug}` / `/rooms/{id}` → `/book` / `/checkout` → Razorpay → `/trips`.
Bleiben's equivalent is the hosted **direct booking page** in the PRD (R1), not
a marketplace.
