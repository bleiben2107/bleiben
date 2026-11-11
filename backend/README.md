# Bleiben backend

Node.js REST API for the Flutter app. Keep this folder as the API root.

```powershell
npm install
npm run dev
```

The server listens on http://localhost:8000. Flutter web and iOS simulator use that host; the Android emulator uses `http://10.0.2.2:8000`.

## Authentication, account & team

| Method & path | What it does |
|---|---|
| `POST /api/auth/signup/request-otp` `{name, email, phone?, country_code}` | Sign up: validates name (letters only) and email (required), phone optional; emails a 6-digit OTP. Nothing is created yet |
| `POST /api/auth/signup/verify-otp` `{email, code}` | Verifies the OTP and creates the account (email verified) |
| `POST /api/auth/login/request-otp` `{identifier}` | Log in with email (OTP by email) or phone (OTP by SMS). Unknown accounts get `action: "signup"` |
| `POST /api/auth/login/verify-otp` `{identifier, code}` | Verifies the OTP and signs in |
| `GET /api/auth/me` | Current user (profile, avatar, verification flags) plus organisation memberships |
| `PATCH /api/account/profile` | Account settings → Personal info (`first_name` required; last/preferred name, date_of_birth, address, city, pincode, profession, hobbies, about ≤ 500, `email_notifications`) |
| `POST /api/account/avatar` `{data}` | Profile photo (base64 JPG/PNG/WebP, ≤ 5 MB) |
| `POST /api/account/contact/request-otp` `{channel: "email"\|"phone", value}` | OTP to a new email / phone (refused if another account has it) |
| `POST /api/account/contact/verify-otp` `{channel, value, code}` | Confirms it and updates the account (sets `email_verified` / `phone_verified`) |
| `POST /api/orgs` `{name}` | Creates an organisation; the caller becomes its Owner (sign-up does this automatically) |
| `PATCH /api/orgs/:id` `{name}` | Rename the organisation (Owner / Manager) |
| `GET/POST /api/orgs/:id/members`, `/invites` | Team list and emailed invites with a role |
| `PATCH/DELETE /api/orgs/:id/members/:memberId` | Change role / remove (the last owner is protected) |
| `POST /api/invites/preview`, `/api/invites/accept` `{token}` | Inspect and accept an emailed invite |

Roles: **Owner**, **Manager**, **Staff**, **Read-only** — see `src/roles.js` for the permission matrix. Module routes mounted with `orgScope` (see `src/middleware/auth.js`) read the organisation from the `X-Org-Id` header.

OTP codes and link tokens are stored only as keyed hashes. Without an SMS provider (`SMS_PROVIDER`), codes are logged and, outside production, returned as `dev_code`; without SMTP, emails are logged and the OTP is returned as `dev_code` too.

Set `USE_LOCAL_STORE=1` to force the JSON file store (for local testing without touching MongoDB).
