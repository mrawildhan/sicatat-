export type ReminderEmailRecord = {
  id: string;
  title: string;
  due_date: string;
  recipient_emails: unknown;
  category?: string | null;
  asset_code?: string | null;
  description?: string | null;
  priority?: string | null;
  assigned_to?: string | null;
  location?: string | null;
};

export type ReminderEmailResult = {
  providerId: string | null;
  recipients: string[];
};

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#039;',
  }[character] ?? character));
}

function safeHeader(value: string) {
  return value.replace(/[\r\n]/g, ' ').trim();
}

function isValidEmail(value: string) {
  return /^[^\s@<>]+@[^\s@<>]+$/.test(value);
}

function base64UrlEncode(value: string) {
  const bytes = new TextEncoder().encode(value);
  let binary = '';
  const chunkSize = 0x8000;
  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function humanDueDate(value: string) {
  const date = new Date(value + 'T00:00:00Z');
  return new Intl.DateTimeFormat('en-GB', {
    day: '2-digit',
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(date);
}

function textOrDash(value: string | null | undefined) {
  const clean = value?.trim();
  return clean && clean.length > 0 ? clean : '—';
}

function subjectPrefix(priority: string | null | undefined) {
  if (priority === 'critical' || priority === 'high') return '[ACTION REQUIRED]';
  return '[SICATAT REMINDER]';
}

async function getGmailAccessToken(
  clientId: string,
  clientSecret: string,
  refreshToken: string,
) {
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }),
  });
  const tokenData = await tokenResponse.json().catch(() => ({}));
  if (!tokenResponse.ok || typeof tokenData.access_token !== 'string') {
    console.error('Gmail OAuth token request failed', tokenResponse.status, tokenData.error);
    throw new Error('Gmail authorization is invalid or expired.');
  }
  return tokenData.access_token as string;
}

export async function sendReminderEmail(
  reminder: ReminderEmailRecord,
): Promise<ReminderEmailResult> {
  const gmailClientId = Deno.env.get('GMAIL_CLIENT_ID');
  const gmailClientSecret = Deno.env.get('GMAIL_CLIENT_SECRET');
  const gmailRefreshToken = Deno.env.get('GMAIL_REFRESH_TOKEN');
  const senderEmail = Deno.env.get('GMAIL_SENDER_EMAIL');
  if (!gmailClientId || !gmailClientSecret || !gmailRefreshToken || !senderEmail) {
    throw new Error(
      'Email delivery is not configured. Add GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET, GMAIL_REFRESH_TOKEN, and GMAIL_SENDER_EMAIL in Supabase secrets.',
    );
  }

  const recipients = Array.isArray(reminder.recipient_emails)
    ? reminder.recipient_emails
        .filter((email): email is string => typeof email === 'string' && isValidEmail(email.trim()))
        .map((email) => email.trim().toLowerCase())
    : [];
  if (recipients.length === 0) {
    throw new Error('This reminder has no valid recipients.');
  }

  const title = safeHeader(reminder.title);
  const dueDate = safeHeader(reminder.due_date);
  const category = textOrDash(reminder.category);
  const assetCode = textOrDash(reminder.asset_code);
  const description = textOrDash(reminder.description);
  const priority = textOrDash(reminder.priority).toUpperCase();
  const assignedTo = textOrDash(reminder.assigned_to);
  const location = textOrDash(reminder.location);
  const humanDue = humanDueDate(dueDate);
  const prefix = subjectPrefix(reminder.priority);
  const html = `
    <div style="font-family:Arial,sans-serif;max-width:640px;color:#17221d">
      <div style="background:#0b3d2e;padding:22px 24px;border-radius:16px 16px 0 0;color:#fff">
        <div style="font-size:12px;letter-spacing:.08em;font-weight:700">SICATAT · OPERATIONAL REMINDER</div>
        <h1 style="margin:8px 0 0;font-size:24px">${escapeHtml(title)}</h1>
      </div>
      <div style="border:1px solid #dce7e0;border-top:0;padding:22px 24px;border-radius:0 0 16px 16px">
        <p style="margin:0 0 16px;color:#9b5c18;font-weight:700">${escapeHtml(priority)} PRIORITY · ACTION REQUIRED</p>
        <table style="width:100%;border-collapse:collapse;font-size:14px">
          <tr><td style="padding:8px 0;color:#6d7a73;width:42%">Due date</td><td style="padding:8px 0;font-weight:700">${escapeHtml(humanDue)}</td></tr>
          <tr><td style="padding:8px 0;color:#6d7a73">Category</td><td style="padding:8px 0;font-weight:700">${escapeHtml(category)}</td></tr>
          <tr><td style="padding:8px 0;color:#6d7a73">Asset / reference</td><td style="padding:8px 0;font-weight:700">${escapeHtml(assetCode)}</td></tr>
          <tr><td style="padding:8px 0;color:#6d7a73">Responsible</td><td style="padding:8px 0;font-weight:700">${escapeHtml(assignedTo)}</td></tr>
          <tr><td style="padding:8px 0;color:#6d7a73">Location</td><td style="padding:8px 0;font-weight:700">${escapeHtml(location)}</td></tr>
        </table>
        <div style="margin-top:16px;padding:14px;background:#f2f8f4;border-radius:10px">
          <strong>Required action</strong><br>${escapeHtml(description)}
        </div>
        <p style="margin:18px 0 0">Please complete the task and update its status in SICATAT.</p>
      </div>
    </div>`;
  const text = [
    'SICATAT OPERATIONAL REMINDER',
    '',
    title,
    'Due date: ' + humanDue,
    'Priority: ' + priority,
    'Category: ' + category,
    'Asset / reference: ' + assetCode,
    'Responsible: ' + assignedTo,
    'Location: ' + location,
    '',
    'Required action: ' + description,
    '',
    'Please complete the task and update its status in SICATAT.',
  ].join('\n');
  const mime = [
    'From: ' + safeHeader(senderEmail),
    'To: ' + recipients.join(', '),
    'Subject: ' + prefix + ' ' + title + ' · due ' + dueDate,
    'MIME-Version: 1.0',
    'Content-Type: multipart/alternative; boundary="sicatat-boundary"',
    '',
    '--sicatat-boundary',
    'Content-Type: text/plain; charset="UTF-8"',
    'Content-Transfer-Encoding: 8bit',
    '',
    text,
    '',
    '--sicatat-boundary',
    'Content-Type: text/html; charset="UTF-8"',
    'Content-Transfer-Encoding: 8bit',
    '',
    html,
    '',
    '--sicatat-boundary--',
  ].join('\r\n');

  const accessToken = await getGmailAccessToken(
    gmailClientId,
    gmailClientSecret,
    gmailRefreshToken,
  );
  const response = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + accessToken,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ raw: base64UrlEncode(mime) }),
  });
  const providerData = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error('Gmail API error', response.status, providerData.error?.status ?? providerData.error);
    throw new Error('Gmail rejected the delivery request. Check the Gmail OAuth configuration.');
  }
  return {
    providerId: typeof providerData.id === 'string' ? providerData.id : null,
    recipients,
  };
}
