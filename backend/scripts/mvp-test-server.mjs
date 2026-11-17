// Local MVP test API: separate JSON data file, email/SMS logged to the console
// (never sent), local iCal links allowed. Not for production.
process.env.USE_LOCAL_STORE = "1";
process.env.DATA_FILE = "./data/e2e-mvp.json";
process.env.SMTP_HOST = ""; // dotenv won't override an existing key → console mailer
process.env.ALLOW_PRIVATE_ICAL = "1";
await import("../src/index.js");
