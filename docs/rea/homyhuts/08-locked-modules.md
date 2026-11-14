# 08 — Locked host modules: Dashboard, Calendar, Reservations, Expenses, Inbox

**Why this is a code REA.** On the REA homyhuts account these five tabs are
locked. Re-checked 2026-11-14: `/dashboard`, `/calendar`, `/reservations`,
`/expenses` and `/inbox` all redirect to `/listing`, with the banner "Connect
your channel manager to unlock all tabs". Opening them live would need a real
channel-manager connection on the account, so they were **not** opened.

Each screen ships as its own lazy-loaded chunk in `host.homeyhuts.com`. This
file is built from those chunks:
- every user-facing string (labels, columns, filters, states, toasts);
- the route table and access rules;
- the API services they call.

So it describes **what each screen contains and does**, not pixel layout.
Treat layout notes as *(inferred)*.

| Module | Route | Chunk | Access feature |
|---|---|---|---|
| Dashboard | `/dashboard` | `index-O5aQSdlq.js` | `dashboard` |
| Calendar | `/calendar` | `index-ByLeDgPA.js` | `calendar` |
| Reservations | `/reservations` | `index-DUD2EX5-.js` | `reservation` |
| Expenses | `/expenses` | `index-D45jb0LP.js` | `expense` |
| Inbox | `/inbox`, `/inbox/:threadId` | `index-C5XO1avl.js` + `thread-CEaMsKmS.js` | `MESSAGE_INBOX` (+ plan add-on) |

All five are hidden or redirected until a channel manager is connected (plan
gate). A co-host also needs `readOnly` or `fullAccess` on the feature.
`readOnly` shows a **"View-only access"** state; dates outside a co-host's
properties show **"No access to these dates"**.

---

## 1. Dashboard

**Header and filters**
- Period: *Last 7 / 30 / 60 days*, *Next 7 / 30 / 60 days*, *Custom range* (D MMM YYYY).
- Scope:
  - *All listings* ("every property you host")
  - *Single listings* ("properties not in a cluster")
  - *Multi listings* ("cluster properties, parents included")
- "Count bookings by": **Check-in date / Check-out date / Booking date**.
- *Filter by location* (All locations), *Filter by property*, *Filter by listing type*, *Clear all*.
- *Refresh figures* button.

**Today panel** (title "Today")
- Tabs: **Check-ins** ("Today's check-ins"), **Check-outs** ("Today's check-outs"),
  **Ongoing stays**, **Arriving in next 2 days**.
- Rows show the source (e.g. *Homeyhuts Direct*, *Offline booking*); a cancelled row is marked. "Show all".
- Empty states: "No bookings here right now." / "No bookings in this range."
- *View all bookings* links to Reservations.

**Quick actions**
- **Add direct booking** ("Offline or phone booking").
- **Add expenses** ("Record a new cost").
- **Properties** ("Manage listings and rates").
- **Manage expenses** ("Full history and reports").

**KPI cards** (each with a description tooltip)

| Card | Definition shown in the UI |
|---|---|
| Net revenue | Sum of the payout recorded against every booking in the period |
| Expenses | Everything recorded as a cost against these properties (rent, staff, cleaning, repairs…), across all categories |
| Net operating income | Net revenue − expenses |
| Occupancy | Share of available time actually booked. A deliberately blocked night still counts as available time |
| Net ADR | Net revenue per booked night |
| Net RevPAR | Net revenue per available night |

**Sections**
- **Where bookings come from:** Source · Nights · Share, "Show sources by",
  *View bookings*. "Blocked nights are left out: a block is not a booking source."
- **Occupancy outlook:** weekly bands: *50% and above*, *25–49%*, *Under 25%*,
  *Not offered*. "Hover any week to read exact dates and nights."
- **Performance:** *Revenue* / *Bookings* / *Nights booked* / *Booked*, "Rank
  properties by", *All properties*, *See all / Show more*.
- **Revenue and expenses:** by month, *Year* picker, "Hover any month to read exact figures".
- **Where money goes:** Category · Amount, *View all categories / Show less*.
  Empty: "No expenses recorded in this range."

**Error state:** "We couldn't load your figures. The service that holds your
properties is not responding. Nothing is wrong with your data." Try again.

**APIs:**
- `booking/api/v1/booking/host-dashboard`, `host-dashboard-info`, `day-wise-count`.
- `total-earning`, `recents`, `payout-summary`, `reservations/summary`.
- `property/api/v1/property/property-occupancy-list`, `property/api/v1/property-expense`.

### Dashboard: validated against the official tutorial

Source: *"How to Use the Homeyhuts Dashboard: Revenue, Expenses & Occupancy
(Web)"* (youtu.be/IVYDzGlmoKQ, 8:31), recorded on a live account with 359
properties. Frames were checked every ~20 s.

**Verdict: the code REA is right on content (sections, KPIs and their
definitions, filters, quick actions, legends) but wrong in places on layout
and naming, and missing some details.** About 85–90% accurate.

| REA claim | Tutorial | Result |
|---|---|---|
| Quick actions: Add direct booking · Add expenses · Properties · Manage expenses (with subtitles) | Same four, same subtitles, row under the header | ✅ |
| Filters: count by check-in/check-out/booking date; period; location; property; listing type | Filter row "Showing [Check-in date] [Last 30 days] 25 Sep – 24 Oct [All locations] [All properties (359)] [All listings]" | ✅ (default period = Last 30 days) |
| KPIs Net revenue, Expenses, NOI, Occupancy, Net ADR, Net RevPAR and their definitions | Same six, same definitions (NOI = net revenue − recorded expenses; ADR per booked night; RevPAR per available night incl. unbooked) | ✅ |
| Today: check-ins, check-outs, ongoing stays, arriving in next 2 days | Same four, as **counts in a right-hand "Today" column** (with today's date), visible next to every section | ✅ content · ⚠️ not tabs |
| "Where bookings come from": Source · Nights · Share, "Show sources by" | Donut + **Revenue / Bookings** toggle; table **Source · Bookings · Nights · Share · Net ADR · Revenue**; the direct row shows "₹… saved in commission" | ✅ + extra columns |
| "Where money goes": Category · Amount | Donut + table **Category · Share · Amount**, small categories grouped as "Other N categories", by expense date | ✅ + Share |
| "Performance" = property ranking ("Rank properties by") | **"Performance" is the top KPI card.** The ranking section is titled **"Properties"**, with a **Revenue / Expenses** toggle; rows show name, location, revenue, % full, net ADR (or expense and % of revenue); "See all 357" | ❌ name / position corrected |
| Revenue and expenses: monthly, year picker, "hover any month" | Same: line chart Jan–Dec with 2026 / 2025 toggle, monthly Revenue · Expenses · Net operating income · margin | ✅ |
| Occupancy outlook: weekly, 50%+ / 25–49% / under 25%, "hover any week" | Same legend; **13 weeks ahead**; selected week shows Booked % and nights booked (e.g. 115 / 1,874) | ✅ |

**Missing from the code REA (add when building):**
- Header: host / home name + today's date. **Alert banners**, e.g. "Airbnb
  withholds 5% TDS on 7 properties: add your PAN…" and "54 bookings missing revenue data".
- **Period comparison:** "vs 26 Aug – 24 Sep", with change on every KPI
  (Revenue ↑34.4%, Occupancy ↑2.4 pts, Net ADR ↓14.8%, Net RevPAR ↑40.9%, NOI ↑4.5%).
- Net revenue split into **Stay / Upsell**; Expenses as **% of revenue**; NOI with **margin %**.
- Occupancy card shows "471 of 8,046 nights".
- Nav on a full account: Dashboard · Calendar · Properties · Reservations ·
  Expenses · **Messages** (unread badge) · Support. Inbox is labelled
  "Messages" in the nav.

---

## 2. Calendar

**Layout:** multi-property grid, listings as rows and dates as columns, moving
in **15-day pages** (*Previous 15 days / Next 15 days*).

**Toolbar**
- *Search by Property Name, Id, City*.
- *Plan Type* filter: All / HH Managed / Subscription / Pay Per Booking / HH Full Service.
- **Entire Mode** toggle ("Show only properties under Entire Place Mode").
- **Flexi Pricing** ("Bulk-update pricing across selected properties").
- **Create Booking**, **Create Offline Booking**.
- **Filters** panel ("Filter by location and occupancy"):
  - *Location* (All locations).
  - **Occupancy** toggle ("Turn on to filter by how booked your properties are").
  - Condition *Less than / Greater than / Between* with a 0–100% slider.
  - *Date range*, *Days*: "Occupancy is measured across this window".
  - *Reset / Apply Filters*. Chips: *Clear location filter*, *Clear occupancy filter*.

**Selecting dates on a row → side panel**
- *Selected Dates*, *Select Date Range*, *Select All*, check-in / check-out.
- **Availability:** *Block dates / Unblock dates*, *Block all dates / Open all dates*.
  - Reason (*Enter reason*) and **Notes** (*Enter notes*).
  - *Overwrite Notes* ("This will update all… / Enter new reason for all blocks").
- **Pricing:** **Set Price** or **Adjust by %**, "New nightly price".
  "Update the nightly price for selected dates, syncing across all connected channels."
- Buttons: *Update Availability*, *Update Pricing & Availability*, *Update Pricing*.
- **Apply on these days** (weekday picker) and **Adjustment**, used by Flexi Pricing.
- **Entire Place Mode** panel (clusters): "Entire Place Mode applied on…".
  Empty: "No Entire Place Mode for this property."

**Toasts:** Dates blocked successfully · Dates opened successfully · Pricing
updated successfully · Notes updated successfully · Failed to update pricing.
Please try again.

**Access:** *View-only access* (co-host read-only); *No access to these dates*.

**APIs:**
- `property/api/v1/property/unified-cal-property-list`, `all-property-price`, `all-property-blocks`.
- `property-block-date` (POST), `/bulk` (POST), `/bulk/delete` (PUT), `/delete` (PUT).
- `/block-date-reasons`, `/update-block-date-reasons`, `/block-history/list|info/{id}`, `/full-sync/{propertyId}`.
- `property-manage-price` (POST), `/bulk-update`, `/by-percentage`.

---

## 3. Reservations

**Tabs:**
- *General* · *Arriving Soon* · **Pending Review** · *Today* · *Checking In* · *Checking Out* · *Others*.
- **Booking requests** · **Offline Bookings** · **Booking Leads** · **Transactions**.

**Filters**
- *Search booking, guest…* / *Search by Booking Id*; *Property* (multi-select, "Property: 1 selected").
- Source: All / Airbnb / Booking.com / **MakeMyTrip/Goibibo** / Homeyhuts Direct…
- **Trip status:** All Status / Upcoming / Ongoing / Completed / Cancelled.
- Plan type: HH Managed / Subscription / Pay Per Booking / HH Full Service.
- Payment: **Online (payment link)** / **Offline (cash / UPI)**.
- Check-In From–To; Book From–To (*Check-In Date* / *Booking Date*); *More filters*; *Apply filters / Clear all*.

**Table columns:**
- **Booking ID** · **Trip Status** · **Check In / Out** · **Guest** · **No of Guests** · **Source**.
- **Payment Status** (*Total / Paid / Balance*) · **Amount** · **Action**.
- *(Internal-only columns also exist: Host, Is Paid Host, Plan Type.)*
- Empty: "No reservations here. Try a different filter, or widen the date range."

**Actions**
- **Create Booking**, **Offline Booking** (with *Offline Booking Payment*).
- *Booking Details* drawer; "Request Cancelled by Guest" state.
- **Export to Excel** ("Pick a date range to export"), *Download Excel report*.
- *Mark as paid*.

**Booking Leads**
- Columns: Property · Check In/Out · User · Status (*Booked / Not Booked*);
  search by property ID or name.
- *Booking Lead Details*: User details (Name, Email, Phone) and booking
  details (Check In, Check Out). Actions *Mark as Booked / Mark as Not Booked*.

**Transactions**
- *Bookings Transaction*: Date · **Guest paid** · **Transaction fee** · **Your payout** ·
  **Expected payout** · Payment Id · Transfer Id; transaction status filter.
  "Released payouts reach your registered bank account within 48 hours."
- **Bookings Adjustments:** Booking · Booking amount · Raised on · Reason ·
  **Owed / Recovered / Outstanding**. "Recovered automatically from your next released payout."
- **Summary:** Last 7 Days / Last 30 Days / Last 12 Months.
- If the user can't see money: "Payments are not shared with you".

**APIs:**
- `booking/api/v1/booking/reservations/list`, `/reservations/summary`, `/booking-status-count`, `/host-booking-list`.
- `/create-direct-booking`, `/create-direct-offline-booking`, `/update-direct-offline-booking/{id}`,
  `/direct-offline-booking/{id}/offline-payment`, `/mark-balance-received/{id}`.
- `/booking-manual-details/{id}`, `/manual-booking-prefill/{propertyId}`.
- `/transactions/{id}`, `/transaction-list`, `/cancel-booking-info/{id}`.
- `/download-direct-offline-invoice-pdf/{id}`, `/host-booking-excel`, `/invoices/list`, `/payment-link`.
- `direct-website/booking-requests/{id}/approve|decline`.
- `booking/api/v1/host-ledger` (adjustments).
- `property/api/v1/property/booking-leads` (+ `/count`, `update-booking-lead-status`).

---

## 4. Expenses

**List**
- Search ("Search expenses by type, amount or payment method").
- *All properties*, *All categories* (from the API), *All payment modes*.
- Period *This month / Custom range* (DD MMM YY), *Amount range* (Min / Max:
  "matches the entry total, not individual expense lines").
- *With / Without attachments*, *Only monthly recurring* ("Your fixed commitments"), *Sort by*.
- *More filters / Apply / Reset / Clear all*.
- **Export expenses to Excel** ("Preparing export", "Expenses exported", "There is nothing to export for these filters").
- Empty: "No expenses yet" / "Nothing matches these filters. Widen the period or clear a filter."

**Add / edit an expense:** Expense Date · Property · Category · Amount ·
Payment mode · Attachments (image viewer with zoom and rotate) · Status. *Edit / Delete*.

**Monthly recurring ("Monthly rules")**
- Turn on "Repeat every month" on an expense type when logging an entry.
- Rule view: *Schedule* (Month · Amount · Status), **Skip** a month with an
  optional reason, **Unskip**, "Amount for the months ahead", *Edit repeating expense*.
- **Stop from today / Stop repeating**, "Delete from this repeat / Skip instead", "Only this month can be removed here."
- Messages:
  - "Repeat updated. Months already filed are unchanged."
  - "This repeat has ended. Its filed months stay in your ledger."
  - "Nothing will file. Unskip a month from Edit, or delete the repeat."
- Months file automatically ("Auto-filed").

**Lock state:** "Expenses are locked" (plan / permission gate).

**API:** `property/api/v1/property-expense` (list, create, update, delete,
recurring rules); categories come from the API (the dashboard says "17 categories").

---

## 5. Inbox

**Conversation list**
- Title "Messages"; search "Search guest, property or message" (starts at 2 letters).
- Filters:
  - *All channels* / channel.
  - *All listings / One listing* ("Choose a listing", "Search listings").
  - **Trip stage** (*Any stage* and stages from the API).
  - **Unread**, starred, archived.
- Sort "**Waiting on you, most urgent first**".
- Empty: "No conversations yet. Guest messages from Airbnb and Booking.com
  appear here once those channels are connected." / "No unread conversations.
  You're all caught up." / "Nothing archived."
- "Stars, priority and filters are yours alone. Your team sees their own."

**Reply times** panel
- *Today / Last 7 days / Last 30 days*. **Typical reply** and **Average reply**, *Within 1 hour*, *Replies*.
- **By agent** ("Agent figures are shown to the host and to co-hosts with full access to messages").

**Thread view**
- Messages, attachments ("Attach a photo").
- **Team note** ("Only your team can see this. It is never sent to the guest"; last edited by…).
- Star / priority / archive / mark read-unread.
- **Quick replies:**
  - Saved answers with a shortcut, e.g. `early`.
  - Template variables: guest first and full name, check-in/out dates, nights,
    guests, property name and description, map link, check-in and check-out
    times, check-in method and instructions, caretaker name and phone, house
    rules, max guests, cancellation policy, Wi-Fi name and password, door code,
    host name, nearest free dates.
  - Starter replies are shared; your own can be edited.
- **Send later:** pick date and time (IST); edit or cancel until it sends. Can't carry a photo.
- **Airbnb actions:**
  - Pre-approve enquiry (24 h); accept or decline a booking request (with a reason for Airbnb).
  - Accept or decline a change; withdraw a proposed change.
  - **Send a special offer** (total price); **hold these dates** (blocks Instant Book for 24 h).
  - **Suggest** nearest free dates ("These dates are taken").

**Access:** a plan add-on (`host-it-yourself/inbox-access`, `inbox-plan-upgrade`) plus feature `MESSAGE_INBOX`.

**APIs:**
- `messaging/api/v1/threads` (+ `/{id}`, `/messages`, `/read|unread|star|priority|archive|note`).
- `/{id}/quick-replies`, `/scheduled`, `/reviews`, `/availability`, `/property-info`, `/requests/{id}/resolve`.
- `/threads/unread-count`, `/reply-times`, `/attachments`.
- Live updates over socket.io (`/engine.io`).

---

## Deep pass from the website code (2026-11-14)

The Dashboard check against the tutorial showed that most "missed" details
(Upsell, % full, "saved in commission", "missing revenue data", the TDS alert)
**were in the shipped code**. The first extractor only read plain `"..."`
literals and skipped template strings and composed text. This second pass, on
the same `host.homeyhuts.com` bundle (`index-OuiqyH0y.js`, unchanged), reads
**all literals in source order (≈ render order)** plus the **structure**:
antd table columns with their `dataIndex` (the data model), tabs, select
options, modals and buttons. No tutorials were used for this pass.

### Calendar: additions and corrections
- **Page order:**
  - Intro banner ("This calendar gives you a unified view across properties.
    Select dates to update availability, pricing, Flexi Pricing, and create an offline booking.").
  - Toolbar: filter button (opens "Filter by location and occupancy"), **Entire
    Mode**, **Flexi Pricing**, ◀ *Previous 15 days* / *Next 15 days* ▶, **Create
    Booking**, **Create Offline Booking**; plan-type select (All / HH Managed /
    Subscription / Pay Per Booking / HH Full Service); a "{n} of {m} properties" counter.
  - Then the grid.
- **Filter state lives in the URL:** `search`, `status=ACTIVATED`, `planType`,
  `from`, `to`, `occupancyRules`, `occupancyOp`, `selectedDays`, `isDesync`
  (= Entire Mode), `locations`. Occupancy defaults: slider 20–80, single value 50.
  Location options come with a property count. Properties load page by page (infinite scroll).
- **Grid:**
  - Fixed **80 px per day** column.
  - Row header: property name, `#{id} | {city}` and an occupancy-rate badge.
  - **Booking bars:** guest name + guest count ("Guests"), the source logo
    (Homeyhuts vs OTA), separate styles for **manual booking** and
    **"Booking Request · Guest"** (pending requests), and **Blocked** bars.
  - The grid is **keyboard-navigable** (arrows, Home / End, Enter, Escape, Tab).
- **Selection panel:**
  - A green / red toggle **Block dates ↔ Unblock dates**.
  - "Block or Unblock selected dates, impacting your property's availability across all connected channels."
  - Per range: *Check In / Check Out*, **Notes** with Edit, reason, Save / Cancel.
  - **Pricing:** *Set Price / Adjust by %* tabs, "Loading price…", *New nightly price*, Apply.
  - Buttons *Update Availability* / *Update Pricing & Availability*; heading "Selected Dates"; *Select All ·*.
- **Co-host messages:**
  - "Your co-host access to Calendar & Pricing is read only, so pricing and
    availability can't be changed here. Ask the property owner to upgrade you to full access."
  - "Your co-host access doesn't cover every property in this selection…".
- **Block API payload:** `{properties:[{propertySerialId}], blockType, reason, dates:[ranges]}`. Reasons can be edited per range or overwritten for all.

### Reservations: additions and corrections
- **Data model** (table `dataIndex`): `formattedBookingId`, `tripStatus`,
  `checkInDate` / `checkOutDate`, `propertyDetails`, `bookingContactDetail`
  (guest), `bookedVia` (source), `guestPaymentStatus`, `priceDetails` (amount),
  `noOfGuests`, `status`, `bookingDetails`.
  - Leads: `propertyTitle`, `userName`, `isBooked`.
  - Internal only: `hostUserDetail`, `_isPaid`, `ConfirmationPipeline`.
- **Payment status values:** *Paid / Pending / Received*, with **Total · Paid · Balance**; "Paid {date}".
- **Booking requests tab** (Instant Booking off): "Hosts have **8 hours** to approve the request. After approval, guests have **4 hours** to make the payment. If not completed, the request is cancelled and the dates become available again."
- **Active-filter chips:** "Source: …", "Property: 1 selected / Properties: n selected", "Status: …", "Plan: …", "Payment: …".
- Page title **"Reservations"**; *Create Booking* and *Offline Booking* buttons; Excel export / download by date range.

### Expenses: additions and corrections
- An **entry** groups several **expense lines** (types). The table rows expand
  ("Show / Hide expense types"); actions *Edit entry / Delete entry*. Delete
  removes the whole entry; skipping affects only "this line" for one month.
- Row metadata: **Added by {name}**, **Added on {date}**, **Repeats monthly**, **Skipped**.
- Filters: amount **Over / Under**, "More filters, n applied", category, property, payment mode, attachments, monthly recurring.
- Export cap: "{n} entries — more than the {max} an export can hold. Narrow the period and try again."
- Empty state: "Log your first bill, salary or repair and it appears here with running totals."
- Repeat behaviour (exact rules):
  - Editing an amount applies to the coming months; months already filed are unchanged.
  - Skipping keeps the month at ₹0 and can be undone.
  - A repeating line can't be deleted from one month alone.
  - Stopping removes upcoming months.

### Inbox: additions and corrections
- **List:** views **All / Starred / Archived**, **Unread**, "Results ·", a "Reply
  time today" chip, Channel filter, listing filter, "Showing: …" chips with
  "Remove filter", and "No conversations on {channel} yet."
- **Thread:**
  - **Scheduled messages:** "Scheduled for … · by …", Send now / Edit / Cancel.
    They are **held, not sent, if the booking changes or is cancelled**.
  - A guest-typing indicator; *Show reservation / request / enquiry*; *Back to conversations*.
- **Conversation details panel:**
  - Trip details and "Your payout {amount} before taxes".
  - "Airbnb adds tax you remit and deducts TDS, so the amount it transfers can differ."
  - *Manage reservation*.
  - Searchable **Property info** with *Put in reply*.
- **Airbnb actions:**
  - Pre-approve: "Pre-approved. The guest has 24 hours to book."
  - Special offer: "Offer sent. The guest has 24 hours to book."; "≈ ₹… per night".
  - Accept: "Accepted. Airbnb confirms the booking shortly."
  - Accept / decline a change, with the reason for declining.
  - "Airbnb needs your answer within …".
  - Suggest free dates from "our calendar".
- **Reviews:**
  - Review the guest (Cleanliness, Communication, Followed the house rules).
  - Public review plus an optional private note.
  - "Would you host them again?"
  - "Send this review to Airbnb? It cannot be changed once it is sent."
  - Reply publicly to the guest's review ("Post this reply? It is public…").
- **Access:** "This conversation isn't shared with you. It belongs to a property where you don't have access to Guest Messages."

**Confidence after this pass:**
- Content and data model: high for all four.
- Layout order: medium-high. Source order follows render order but not exact positions.

The same extraction applied to the Dashboard would have caught every
"missing" item from the tutorial check except the visual chart types (donut, line).

## Validation against the official tutorial (2026-11-14)

Checked against Homeyhuts' own video *"Entire Place Mode (Web) | Pause Child
Listings & Sell Your Entire Property"* (youtu.be/d12r8WUnqNk, 5:07). It was
recorded on a fully unlocked host account (on-screen date 21 Jul 2026), and
frames were captured every ~20 s. It covers the **Calendar** and **Magic
Cluster / Entire Place Mode**; it doesn't show Dashboard, Reservations,
Expenses or Inbox content.

**Confirmed (matches the code REA):**
- Calendar route `/calendar` (with `?search=`), a multi-property timeline with
  dates as columns and a **nightly price in every cell**, ◀ ▶ paging and a date picker.
- Calendar toolbar has **Entire Mode** with the exact tooltip "Show only
  properties under Entire Place Mode", plus **Flexi Pricing** and **Create Offline Booking**.
- Entire Place Mode is built on the **de-sync rule** API. Turning on Entire
  Mode adds `isDesync=true` to the calendar URL, matching
  `property/api/v1/de-sync-rule` (POST / PATCH / DELETE) in raw/endpoints-host-panel.txt.
- Properties → **Magic Cluster** table: Cluster Name · Cluster Id · Mapping ·
  Entire Place Mode · Action, plus New Cluster.
- Route `listing/cluster/:id/entire-place-mode` (owner-only screen in the route table).
- The cluster detail page shows **Source → Target** sync: "Availability is
  automatically synchronized across all listings in a cluster… when booked or
  blocked on [source], targets are blocked and reopened when they free up".

**New detail the code REA didn't have:**
- Calendar intro banner: "This calendar gives you a unified view across
  properties. Select dates to update availability, pricing, Flexi Pricing, and
  create an offline booking."
- Calendar rows: name, `#ID | City`, a red **bedroom badge** (5 BR / 2 BR / 1 BR), and
  a vertical *Entire Mode* tag when a rule applies. A property count "Properties (6)" sits above the search.
- Bar labels in the grid: **Blocked** (on the parent), **Parent Listing Blocked**
  (children of a blocked parent), **Entire Place Mode** (purple, children during a rule).
- **Entire Place Mode page:**
  - Tabs **All / Active / Upcoming / Expired** (with counts).
  - Table: Date Range · Status (ACTIVE) · Days ("Every day") · Children Blocked ("4 child listings") · Reason.
  - Each row has an on/off **toggle** and **Edit**. Button **+ Activate Entire Place Mode**.
- **Activate Entire Place Mode** drawer:
  - Warning: "During the selected dates only the entire property is bookable.
    Child listings are blocked for this period and unblocked automatically afterward."
  - Affected listings: parent "stays bookable"; "All N child listings will be blocked" (list with IDs).
  - **Date Range \***, **Days of week \*** (Su Mo Tu We Th Fr Sa toggles), **Reason** (optional, max 45 characters).

**Corrections / caveats:**
- The calendar toolbar button is labelled **"Occupancy Filter"**. It opens the location and occupancy panel described above.
- No *Plan Type* filter and no separate *Create Booking* button appear in that
  host's toolbar. They're likely internal/admin-only or plan-dependent, so
  treat them as optional.
- That host's nav was **Dashboard · Calendar · Properties · Reservations · Host
  Support** (WhatsApp icon): no Expenses or Inbox tabs. So both are add-ons /
  feature-gated, not always present. The video (Jul 2026) also predates today's
  bundle, which labels support "Support".

## What this means for Bleiben R1 (see 07)

| Module | Take for R1 | Leave for later |
|---|---|---|
| Dashboard | Period picker, Today tabs (check-ins / check-outs / in-house / arriving 2 days), quick actions, booking/source counts, payment overview, clear empty and error states | ADR, RevPAR, NOI, occupancy outlook, performance ranking, expense widgets |
| Calendar | Timeline grid with 15-day paging, select dates → block/unblock with reason + notes, set price for dates, create booking from the grid, toasts, view-only state | Flexi pricing by %, occupancy filters, Entire Place Mode, plan-type filters |
| Reservations | Tabs (upcoming / today / checking in / out / cancelled), filters (property, source, status, check-in range, booking date), the column set, create offline booking + record payment, export | Booking leads, OTA request approval, payouts/adjustments ledger |
| Expenses | — (R2) | Copy the structure above when it starts |
| Inbox | — (R1 = notifications only) | Thread model, quick-reply variables (reuse them for R1 email templates), send later |
