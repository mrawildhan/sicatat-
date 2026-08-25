// Invoked once a day by Supabase Cron. This function deliberately disables JWT
// verification at the gateway, then verifies an unguessable server-side header
// sourced from Supabase Vault before sending anything.

import { createClient } from 'npm:@supabase/supabase-js@2';

import { sendReminderEmail } from '../_shared/reminder_email.ts';

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function dateInWita() {
  const pieces = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Makassar',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const value = (type: string) => pieces.find((part) => part.type === type)?.value ?? '';
  return value('year') + '-' + value('month') + '-' + value('day');
}

function daysBetween(startDate: string, endDate: string) {
  const start = Date.parse(startDate + 'T00:00:00Z');
  const end = Date.parse(endDate + 'T00:00:00Z');
  return Math.round((end - start) / 86400000);
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed.' }, 405);
  const expectedSecret = Deno.env.get('REMINDER_CRON_SECRET');
  if (!expectedSecret || req.headers.get('x-reminder-cron-secret') !== expectedSecret) {
    return json({ ok: false, error: 'Unauthorized scheduler request.' }, 401);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(supabaseUrl, serviceRoleKey);
  const today = dateInWita();

  try {
    const { data: reminders, error } = await admin
      .from('operational_reminder')
      .select('id,title,due_date,recipient_emails,category,asset_code,description,priority,assigned_to,location,reminder_offsets_days')
      .eq('status', 'open')
      .gte('due_date', today)
      .limit(100);
    if (error) throw error;

    const dueToday = (reminders ?? []).filter((reminder) => {
      const offsets = Array.isArray(reminder.reminder_offsets_days)
        ? reminder.reminder_offsets_days.filter((value): value is number => typeof value === 'number')
        : [];
      return offsets.includes(daysBetween(today, reminder.due_date));
    });
    let sent = 0;
    let skipped = 0;
    let failed = 0;

    for (const reminder of dueToday) {
      const offset = daysBetween(today, reminder.due_date);
      const { data: delivery, error: claimError } = await admin
        .from('operational_reminder_delivery')
        .insert({
          reminder_id: reminder.id,
          delivery_type: 'scheduled',
          scheduled_offset_days: offset,
          due_date_snapshot: reminder.due_date,
          recipients: reminder.recipient_emails,
          status: 'sending',
        })
        .select('id')
        .single();
      if (claimError || !delivery) {
        if (claimError?.code === '23505') {
          skipped += 1;
          continue;
        }
        console.error('Unable to claim scheduled reminder', reminder.id, claimError);
        failed += 1;
        continue;
      }

      try {
        const result = await sendReminderEmail(reminder);
        await admin
          .from('operational_reminder_delivery')
          .update({
            status: 'sent',
            provider_id: result.providerId,
            recipients: result.recipients,
            sent_at: new Date().toISOString(),
          })
          .eq('id', delivery.id);
        await admin
          .from('operational_reminder')
          .update({ last_sent_at: new Date().toISOString() })
          .eq('id', reminder.id);
        await admin.from('operational_reminder_activity').insert({
          reminder_id: reminder.id,
          action: 'email_sent',
          note: 'Automatic H-' + offset + ' email sent to ' + result.recipients.length + ' recipient(s).',
          details: { delivery_id: delivery.id, delivery_type: 'scheduled', offset_days: offset },
        });
        sent += 1;
      } catch (sendError) {
        const message = sendError instanceof Error ? sendError.message : 'Unable to send reminder email.';
        await admin
          .from('operational_reminder_delivery')
          .update({ status: 'failed', error_message: message })
          .eq('id', delivery.id);
        console.error('Scheduled reminder failed', reminder.id, message);
        failed += 1;
      }
    }
    return json({ ok: true, date: today, considered: dueToday.length, sent, skipped, failed });
  } catch (error) {
    console.error(error);
    return json({ ok: false, error: error instanceof Error ? error.message : 'Unable to dispatch reminders.' }, 500);
  }
});
