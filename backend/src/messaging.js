import nodemailer from "nodemailer";

import { config } from "./config.js";

/** Raised when the SMTP server rejects or can't deliver a message. */
export class EmailDeliveryError extends Error {
  constructor(cause) {
    super("We couldn't send the email right now. Please try again in a moment.");
    this.name = "EmailDeliveryError";
    this.cause = cause;
  }
}

/**
 * Email sender. Uses SMTP when SMTP_HOST/USER/PASS are set; otherwise logs
 * messages to the console so local development works without credentials.
 */
export function createMailer(smtp = config.smtp) {
  const configured = Boolean(smtp.host && smtp.user && smtp.pass);
  const transport = configured
    ? nodemailer.createTransport({
        host: smtp.host,
        port: smtp.port,
        secure: smtp.secure,
        auth: { user: smtp.user, pass: smtp.pass },
      })
    : null;

  return {
    configured,
    async verify() {
      if (!transport) {
        return false;
      }
      await transport.verify();
      return true;
    },
    async send({ to, subject, text, html }) {
      if (!transport) {
        console.log(`[mail:dev] to=${to} subject="${subject}"\n${text}`);
        return { delivered: false };
      }
      try {
        const info = await transport.sendMail({ from: smtp.from, to, subject, text, html });
        // Keep the provider's receipt so delivery problems can be traced.
        console.log(
          `[mail] to=${to} subject="${subject}" accepted=${info.accepted?.length ?? 0} rejected=${info.rejected?.length ?? 0} id=${info.messageId} response="${info.response}"`,
        );
        if (info.rejected?.length) {
          throw new Error(`Recipient rejected: ${info.rejected.join(", ")}`);
        }
      } catch (err) {
        console.error(`[mail] send to ${to} failed: ${err.code ?? ""} ${err.message}`);
        throw new EmailDeliveryError(err);
      }
      return { delivered: true };
    },
  };
}

/** SMS sender. No provider is integrated yet, so codes are only logged. */
export function createSmsSender(sms = config.sms) {
  return {
    configured: Boolean(sms.provider),
    async send({ to, text }) {
      // TODO(sms): plug in an SMS/WhatsApp provider (e.g. MSG91, Twilio) here.
      console.log(`[sms:dev] to=${to} ${text}`);
      return { delivered: false };
    },
  };
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

function layout(title, body, cta) {
  return `<!doctype html><html><body style="margin:0;background:#f6f1e7;font-family:Arial,sans-serif;color:#1c241f">
<table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:32px 16px">
<table width="100%" style="max-width:480px;background:#fff;border-radius:16px;padding:32px">
<tr><td style="font-size:24px;font-weight:bold;color:#1f4d3a;padding-bottom:16px">Bleiben</td></tr>
<tr><td style="font-size:18px;font-weight:bold;padding-bottom:12px">${escapeHtml(title)}</td></tr>
<tr><td style="font-size:15px;line-height:1.5;padding-bottom:24px">${body}</td></tr>
${cta ? `<tr><td><a href="${escapeHtml(cta.url)}" style="display:inline-block;background:#1f4d3a;color:#fff;text-decoration:none;padding:12px 22px;border-radius:999px;font-weight:bold">${escapeHtml(cta.label)}</a></td></tr>` : ""}
<tr><td style="font-size:12px;color:#5b6861;padding-top:24px">If you didn't request this, you can ignore this email.</td></tr>
</table></td></tr></table></body></html>`;
}

export function otpEmail(code, minutes, purpose) {
  const action =
    purpose === "signup"
      ? "finish creating your Bleiben account"
      : purpose === "change_email"
        ? "confirm this email address for your Bleiben account"
        : "sign in to Bleiben";
  return {
    subject: `${code} is your Bleiben verification code`,
    text: `Your Bleiben verification code is ${code}.

Enter it to ${action}. It expires in ${minutes} minutes. Never share this code with anyone.`,
    html: layout(
      "Your verification code",
      `Enter this code to ${action}:<div style="font-size:34px;font-weight:bold;letter-spacing:10px;color:#1f4d3a;padding:18px 0">${escapeHtml(code)}</div>It expires in ${minutes} minutes. Never share this code with anyone — Bleiben will never ask for it.`,
      null,
    ),
  };
}

export function inviteEmail({ url, orgName, inviterName, role, days }) {
  const who = inviterName ? escapeHtml(inviterName) : "A teammate";
  return {
    subject: `You're invited to ${orgName} on Bleiben`,
    text: `${inviterName || "A teammate"} invited you to join ${orgName} on Bleiben as ${role}.\n\nAccept: ${url}\n\nThis invite expires in ${days} days.`,
    html: layout(
      `Join ${orgName} on Bleiben`,
      `${who} invited you to join <b>${escapeHtml(orgName)}</b> as <b>${escapeHtml(role)}</b>. The invite expires in ${days} days.`,
      { url, label: "Accept invite" },
    ),
  };
}
