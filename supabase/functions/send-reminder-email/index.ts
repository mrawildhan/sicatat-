// Sends an operational reminder through Resend. The API key lives only in the
// Supabase Function secret store; it must never be copied into Flutter or an APK.

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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed.' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const resendApiKey = Deno.env.get('RESEND_API_KEY');
  const fromEmail = Deno.env.get('RESEND_FROM_EMAIL');

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

    if (!resendApiKey || !fromEmail) {
      return json({
        ok: false,
        error: 'Email delivery is not configured. Set RESEND_API_KEY and RESEND_FROM_EMAIL in Supabase secrets.',
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
          .filter((email): email is string => typeof email === 'string' && email.includes('@'))
          .map((email) => email.trim().toLowerCase())
      : [];
    if (recipients.length === 0) {
      return json({ ok: false, error: 'This reminder has no valid recipients.' }, 400);
    }

    const title = String(reminder.title);
    const dueDate = String(reminder.due_date);
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + resendApiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: fromEmail,
        to: recipients,
        subject: 'SICATAT reminder: ' + title,
        text: title + '\n\nDue date: ' + dueDate + '\n\nThis operational reminder was sent from SICATAT.',
        html: '<h2>SICATAT operational reminder</h2><p><strong>' +
          escapeHtml(title) +
          '</strong></p><p>Due date: <strong>' +
          escapeHtml(dueDate) +
          '</strong></p><p>This message was sent from SICATAT.</p>',
      }),
    });
    const providerData = await response.json().catch(() => ({}));
    if (!response.ok) {
      console.error('Resend error', response.status, providerData);
      return json({ ok: false, error: 'The email provider rejected the delivery request.' }, 502);
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
      error: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});
