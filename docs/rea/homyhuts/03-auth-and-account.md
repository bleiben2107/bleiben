# 03 — Auth and account (homeyhuts.com)

Live-captured while logged in (2026-11-11), plus endpoints from the bundle.
Bleiben implements this in `backend/src/routes/auth.js`, `backend/src/routes/account.js`
and `frontend/lib/features/auth/` and `frontend/lib/features/account/`.

## Sign up / log in — `/signup-signin`

One page, two modes. **No passwords.**

| Step | Log in | Sign up |
|---|---|---|
| 1 | Field **"Enter Email / Phone Number \*"** → Continue | **Full name \*** (letters only, ≤ 75), **Email \*** (mandatory), **Phone** (optional, with country code) → Send OTP |
| 2 | "Enter OTP — please enter the OTP sent to …", 6 digits, resend after a countdown | Same OTP screen; the OTP goes to the **email** |
| 3 | Verified → signed in | Account is created **only after** the OTP is verified |
| Errors | Unknown email/phone → offered "Sign up" | Existing email/phone → offered "Log in" |
| Phone OTP | Sent **via SMS or WhatsApp** ("Please enter the OTP sent to … via SMS or WhatsApp"), Resend after 60 s, Submit / Close | — |

Host sign-up is a separate form at `/start-trial` ("14 days free trial"): Full
Name, Email, Phone (all required), plus acceptance of the Master Service
Terms. See 06.

After success the user returns to the **page they came from** (via the
`redirect` cookie or `redirectUrl`), normally the homepage, now signed in (the
avatar shows the initial). **Nothing is forced** (no setup wizard). Hosting
starts only when the user clicks "Start free trial" / "List your property".

Endpoints (`/auth/api/v1`):
- `POST otp/create-otp`, `POST otp/verify-otp`: generic OTP.
- `POST login-with-otp` (phone), `POST login-with-email-otp`, `POST verify-login-otp`, `POST verify-email-otp`.
- `POST users/guest-register`: create a guest account.
- `POST users/check-email-verification-status`, `POST users/verify-email-link`, `POST …/resend-verification-link`.
- `GET users/profile-info`: who am I. The host panel calls this to bootstrap.

## Account settings — `/account/*` (portal)

Layout: top bar (logo · "List Your Property" · avatar menu). Left card:
"‹ Account Settings", then **Personal info**, then **Account Verifications** with
a red **Pending** badge. Right card: the content.

### Personal info — `/account/profile-info`

| Block | Details |
|---|---|
| Header | "Personal Info"; large round avatar with the initial and a camera **Edit** chip (change profile photo) |
| Email | Value + **Edit** (change email, confirmed by OTP to the new address; `PUT users/user-email-update`) |
| Phone Number | `+91` + **Add** / Edit (confirmed by OTP; `PUT users/user-phone-update`) |
| Name | First Name \*, Last Name, Preferred Name |
| Personal | Date of Birth (calendar picker) |
| Address | Address1, Address2, Select Country, Select State (from `masters/country`, `masters/state?countryId=`), City, Pincode |
| About you (shown only to hosts of confirmed bookings) | Profession, Hobbies, Pet Name, Known Languages, Where did I go to school?, About yourself (max 500) |
| Save | One **Save** button for the form |
| Email notifications | Toggle |
| Deactivate | "Do you want to deactivate your account?" → Deactivate (`PATCH users/status/{id}`) |

### Account Verifications — `/account/verification`

- Header "Account Verification" with a **Pending** badge.
- Card "Verify your identity": a one-time check, about a minute.
- Homeyhuts collects the **ID card + selfie only in its mobile app**. The web
  shows App Store / Play Store links, a QR code, and three steps: get the app,
  sign in, then Menu → Profile & Settings → Account Verification.
- Endpoints: `GET user-verification/verification-info`; admin review uses
  `user-verification/aadhar-detail/{id}` and `…/admin/{id}/review`.
- Bleiben (no app yet) shows a checklist instead: email ✓, phone (OTP),
  government ID "coming soon".

## Host panel account — `host.homeyhuts.com/account`

Tabs: **profile** | **verification** | **payout-details**.
- Payout details = host bank account: `POST auth/api/v1/host-user/host-bank-detail`, `GET …/get-bank-detail/{id}`.
- `/account/subscription-billings`: plan type, dues list, pay one or all dues
  via Razorpay, billing banner, referral summary (`/host-it-yourself/api/v1/*`).

Bleiben: payouts and billing are **later** (payments are out of the current scope).
