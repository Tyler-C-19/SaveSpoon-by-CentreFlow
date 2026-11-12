const nodemailer = require('nodemailer');

const CONTENT = {
  verify_email: {
    subject: 'Email verification OTP',
    action: 'verify your email',
  },
  reset_password: {
    subject: 'Password reset OTP',
    action: 'reset your password',
  },
  change_email: {
    subject: 'Email change OTP',
    action: 'confirm your new email',
  },
};

let transporter;

function getTransporter() {
  if (!transporter) {
    transporter = nodemailer.createTransport({
      service: 'gmail',
      connectionTimeout: 8000,
      auth: {
        user: process.env.EMAIL_USER,
        pass: (process.env.EMAIL_APP_PASSWORD || '').replace(/\s/g, ''),
      },
    });
  }
  return transporter;
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function buildOtpEmail(name, code, purpose) {
  const { subject, action } = CONTENT[purpose];
  const intro = `Your OTP to ${action} is valid for the next 5 minutes. `
    + 'Please enter the OTP in the SaveSpoon app as soon as possible. Do not share it with anyone.';
  const notYou = "If you didn't request this, you can safely ignore this email.";

  const text = `Hi ${name},\n\n${intro}\n\nYour OTP is: ${code}\n\n${notYou}\n`;

  // A table row keeps the six boxes on one line and lets them narrow on small screens.
  const digits = [...code]
    .map((digit, index) => `<td style="width:16.66%;padding-right:${index === code.length - 1 ? 0 : 6}px;">`
      + '<span style="display:block;height:50px;line-height:50px;'
      + 'background:#ffffff;border-radius:8px;text-align:center;font-family:Consolas,Menlo,monospace;'
      + `font-size:26px;font-weight:700;color:#1B8A3A;">${digit}</span></td>`)
    .join('');

  const html = `<!doctype html>
<html>
<body style="margin:0;padding:24px;background:#f4f7f4;font-family:Arial,Helvetica,sans-serif;color:#1f2937;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;margin:0 auto;background:#ffffff;border-radius:16px;">
    <tr>
      <td style="padding:20px 28px;background:#28A745;border-radius:16px 16px 0 0;color:#ffffff;font-size:22px;font-weight:700;">SaveSpoon</td>
    </tr>
    <tr>
      <td style="padding:28px;font-size:15px;line-height:1.6;">
        <p style="margin:0 0 16px;">Hi ${escapeHtml(name)},</p>
        <p style="margin:0 0 20px;">${escapeHtml(intro)}</p>
        <div style="padding:18px 20px;background:#E8F5EA;border-radius:12px;">
          <div style="margin-bottom:12px;font-size:14px;font-weight:700;">Code requested</div>
          <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;max-width:270px;"><tr>${digits}</tr></table>
        </div>
        <p style="margin:20px 0 0;font-size:13px;color:#6b7280;">${escapeHtml(notYou)}</p>
      </td>
    </tr>
  </table>
</body>
</html>`;

  return { subject, text, html };
}

function buildNoticeEmail(name, subject, message) {
  const notYou = "If this wasn't you, reset your password in the SaveSpoon app straight away.";
  const text = `Hi ${name},\n\n${message}\n\n${notYou}\n`;

  const html = `<!doctype html>
<html>
<body style="margin:0;padding:24px;background:#f4f7f4;font-family:Arial,Helvetica,sans-serif;color:#1f2937;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;margin:0 auto;background:#ffffff;border-radius:16px;">
    <tr>
      <td style="padding:20px 28px;background:#28A745;border-radius:16px 16px 0 0;color:#ffffff;font-size:22px;font-weight:700;">SaveSpoon</td>
    </tr>
    <tr>
      <td style="padding:28px;font-size:15px;line-height:1.6;">
        <p style="margin:0 0 16px;">Hi ${escapeHtml(name)},</p>
        <p style="margin:0 0 20px;">${escapeHtml(message)}</p>
        <p style="margin:20px 0 0;font-size:13px;color:#6b7280;">${escapeHtml(notYou)}</p>
      </td>
    </tr>
  </table>
</body>
</html>`;

  return { subject, text, html };
}

function buildPasswordChangedEmail(name) {
  return buildNoticeEmail(
    name,
    'Your password was changed',
    'The password for your SaveSpoon account was just changed. All other active sessions have been logged out.'
  );
}

function buildEmailChangedEmail(name, newEmail) {
  return buildNoticeEmail(
    name,
    'Your email was changed',
    `The email for your SaveSpoon account was just changed to ${newEmail}. This address will no longer receive account emails.`
  );
}

const RESEND_URL = 'https://api.resend.com/emails';

async function sendWithResend(to, content) {
  const response = await fetch(RESEND_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: process.env.EMAIL_FROM,
      to: [to],
      reply_to: process.env.EMAIL_REPLY_TO || undefined,
      ...content,
    }),
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) {
    const detail = await response.json().catch(() => ({}));
    throw new Error(`Resend returned ${response.status}${detail.message ? `: ${detail.message}` : ''}`);
  }
}

// Resend when its key is set, otherwise Gmail.
function send(to, content) {
  if (process.env.RESEND_API_KEY) return sendWithResend(to, content);
  return getTransporter().sendMail({
    from: `SaveSpoon <${process.env.EMAIL_USER}>`,
    to,
    ...content,
  });
}

async function sendOtpEmail(to, name, code, purpose) {
  await send(to, buildOtpEmail(name, code, purpose));
}

async function sendPasswordChangedEmail(to, name) {
  await send(to, buildPasswordChangedEmail(name));
}

async function sendEmailChangedEmail(to, name, newEmail) {
  await send(to, buildEmailChangedEmail(name, newEmail));
}

module.exports = {
  sendOtpEmail, buildOtpEmail, sendPasswordChangedEmail, buildPasswordChangedEmail, sendEmailChangedEmail, buildEmailChangedEmail,
};
