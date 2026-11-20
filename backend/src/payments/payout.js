import { InputError, nowIso } from "../bookings/core.js";
import { openSecret, sealSecret } from "./gateway.js";

/**
 * Bank account and tax info (Account settings), one per organisation.
 * Where the host receives money: bank transfer details and UPI ID. The
 * account number and PAN are stored encrypted. Used to show "received in"
 * on recorded UPI / bank payments, and — when online payments are off — to
 * let guests pay the host directly after a booking request.
 */
const IFSC_RE = /^[A-Z]{4}0[A-Z0-9]{6}$/;
const PAN_RE = /^[A-Z]{5}[0-9]{4}[A-Z]$/;
const GSTIN_RE = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
const UPI_RE = /^[A-Za-z0-9._-]{2,256}@[A-Za-z][A-Za-z0-9]{1,63}$/;
const NAME_RE = /^[\p{L}\p{M}][\p{L}\p{M} .'&-]*$/u;
export const ACCOUNT_TYPES = { savings: "Savings", current: "Current" };

const last4 = (s) => (s ? `••••${String(s).slice(-4)}` : null);

export async function payoutDoc(db, orgId) {
  return db.findDoc("payout_details", { org_id: orgId });
}

/** What the host sees (sensitive numbers masked). */
export function payoutView(p) {
  if (!p) return { configured: false, share_with_guests: true, account_types: ACCOUNT_TYPES };
  return {
    configured: true,
    bank_name: p.bank_name,
    beneficiary_name: p.beneficiary_name,
    account_number_masked: last4(openSecret(p.account_number)),
    ifsc: p.ifsc,
    account_type: p.account_type,
    gstin: p.gstin ?? "",
    gst_business_name: p.gst_business_name ?? "",
    pan_masked: last4(openSecret(p.pan)),
    upi_id: p.upi_id ?? "",
    share_with_guests: p.share_with_guests !== false,
    updated_at: p.updated_at,
    account_types: ACCOUNT_TYPES,
  };
}

/** Short "received in" labels for the record-payment dialog. */
export function payoutTargets(p) {
  if (!p) return { upi: null, bank: null };
  return {
    upi: p.upi_id || null,
    bank: `${p.bank_name} ${last4(openSecret(p.account_number))} · ${p.beneficiary_name}`,
  };
}

/** Details a guest needs to pay the host directly (booking requests only). */
export function guestPayDetails(p, { amount, reference, payee }) {
  if (!p || p.share_with_guests === false) return null;
  return {
    upi_id: p.upi_id || null,
    payee: payee || p.beneficiary_name,
    amount,
    reference,
    bank: {
      bank_name: p.bank_name,
      beneficiary_name: p.beneficiary_name,
      account_number: openSecret(p.account_number),
      ifsc: p.ifsc,
      account_type: ACCOUNT_TYPES[p.account_type] ?? p.account_type,
    },
  };
}

/** Validates the form; keeps the saved account number / PAN when left empty. */
export function payoutInput(body, existing) {
  const b = body ?? {};
  const str = (v) => String(v ?? "").trim();
  const bankName = str(b.bank_name);
  const beneficiary = str(b.beneficiary_name);
  const accNew = str(b.account_number).replace(/\s/g, "");
  const ifsc = str(b.ifsc).toUpperCase();
  const type = str(b.account_type) || "savings";
  const gstin = str(b.gstin).toUpperCase();
  const gstName = str(b.gst_business_name);
  const panNew = str(b.pan).toUpperCase();
  const upi = str(b.upi_id);

  if (bankName.length < 2) throw new InputError("Enter the bank name");
  if (!NAME_RE.test(beneficiary)) throw new InputError("Enter the beneficiary name as on the bank account (letters only)");
  if (accNew && !/^\d{9,18}$/.test(accNew)) throw new InputError("Account number should be 9 to 18 digits");
  if (!accNew && !existing?.account_number) throw new InputError("Enter the account number");
  if (accNew && b.confirm_account_number !== undefined && str(b.confirm_account_number).replace(/\s/g, "") !== accNew) {
    throw new InputError("Account numbers don't match");
  }
  if (!IFSC_RE.test(ifsc)) throw new InputError("Enter a valid IFSC code (e.g. HDFC0001234)");
  if (!ACCOUNT_TYPES[type]) throw new InputError("Choose the account type");
  if (gstin && !GSTIN_RE.test(gstin)) throw new InputError("Enter a valid 15-character GST number");
  if (panNew && !PAN_RE.test(panNew)) throw new InputError("Enter a valid PAN (e.g. ABCDE1234F)");
  if (!panNew && !existing?.pan) throw new InputError("Enter the PAN number");
  if (upi && !UPI_RE.test(upi)) throw new InputError("Enter a valid UPI ID (e.g. name@okhdfcbank)");

  return {
    bank_name: bankName.slice(0, 80),
    beneficiary_name: beneficiary.slice(0, 80),
    account_number: accNew ? sealSecret(accNew) : existing.account_number,
    ifsc,
    account_type: type,
    gstin,
    gst_business_name: gstName.slice(0, 120),
    pan: panNew ? sealSecret(panNew) : existing.pan,
    upi_id: upi,
    share_with_guests: b.share_with_guests !== false,
    updated_at: nowIso(),
  };
}
