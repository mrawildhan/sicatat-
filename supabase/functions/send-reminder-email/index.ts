// Sends an operational reminder through the Gmail API. OAuth credentials live
// only in the Supabase Function secret store; they must never be copied into
// Flutter, an APK, Git, or chat.

import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed.' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const gmailClientId = Deno.env.get('GMAIL_CLIENT_ID');
  const gmailClientSecret = Deno.env.get('GMAIL_CLIENT_SECRET');
  const gmailRefreshToken = Deno.env.get('GMAIL_REFRESH_TOKEN');
  const senderEmail = Deno.env.get('GMAIL_SENDER_EMAIL');

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ ok: false, error: 'No login session.' }, 401);

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user: authUser }, error: authError } = await callerClient.auth.getUser();
    if (authError || !authUser?.email) {
      return json({ ok: false, error: 'Invalid session. Please log in again.' }, 401);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const callerNik = authUser.email.replace('@sicatat.local', '');
    const { data: callerProfile, error: callerError } = await admin
      .from('app_user')
      .select('role,is_active')
      .eq('nik', callerNik)
      .single();
    if (callerError || !callerProfile || callerProfile.role !== 'admin' || !callerProfile.is_active) {
      return json({ ok: false, error: 'Only active admins can send reminder emails.' }, 403);
    }

    if (!gmailClientId || !gmailClientSecret || !gmailRefreshToken || !senderEmail) {
      return json({
        ok: false,
        error: 'Email delivery is not configured. Add GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET, GMAIL_REFRESH_TOKEN, and GMAIL_SENDER_EMAIL in Supabase secrets.',
      }, 503);
    }

    const body = await req.json().catch(() => ({}));
    const reminderId = String(body.reminder_id ?? '').trim();
    if (!reminderId) {
      return json({ ok: false, error: 'Reminder ID is required.' }, 400);
    }

    const { data: reminder, error: reminderError } = await admin
      .from('operational_reminder')
      .select('title,due_date,recipient_emails')
      .eq('id', reminderId)
      .single();
    if (reminderError || !reminder) {
      return json({ ok: false, error: 'Reminder was not found.' }, 404);
    }
    const recipients = Array.isArray(reminder.recipient_emails)
      ? reminder.recipient_emails
          .filter((email): email is string => typeof email === 'string' && isValidEmail(email.trim()))
          .map((email) => email.trim().toLowerCase())
      : [];
    if (recipients.length === 0) {
      return json({ ok: false, error: 'This reminder has no valid recipients.' }, 400);
    }

    const title = safeHeader(String(reminder.title));
    const dueDate = safeHeader(String(reminder.due_date));
    const html = '<h2>SICATAT operational reminder</h2><p><strong>' +
      escapeHtml(title) +
      '</strong></p><p>Due date: <strong>' +
      escapeHtml(dueDate) +
      '</strong></p><p>This message was sent from SICATAT.</p>';
    const text = 'SICATAT operational reminder\n\n' + title +
      '\nDue date: ' + dueDate + '\n\nThis message was sent from SICATAT.';
    const mime = [
      'From: ' + safeHeader(senderEmail),
      'To: ' + recipients.join(', '),
      'Subject: SICATAT reminder: ' + title,
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
      return json({ ok: false, error: 'Gmail rejected the delivery request. Check the Gmail OAuth configuration.' }, 502);
    }

    return json({
      ok: true,
      provider_id: typeof providerData.id === 'string' ? providerData.id : null,
      recipient_count: recipients.length,
    });
  } catch (error) {
    console.error(error);
    return json({
      ok: false,
      error: error instanceof Error ? error.message : 'Unable to send the reminder email.',
    }, 500);
  }
});
