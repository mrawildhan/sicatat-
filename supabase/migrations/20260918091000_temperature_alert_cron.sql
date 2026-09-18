-- Scan for critical temperatures every 5 minutes. The function only emails
-- values it has not emailed before (temperature_alert.source_key is unique).
select cron.unschedule(jobid)
from cron.job
where jobname = 'sicatat-dispatch-temperature-alerts';

select cron.schedule(
  'sicatat-dispatch-temperature-alerts',
  '*/5 * * * *',
  $$
    select net.http_post(
      url := 'https://ofczleeyqrxyuuupzirq.supabase.co/functions/v1/dispatch-temperature-alerts',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-reminder-cron-secret', (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'sicatat_reminder_cron_secret'
        )
      ),
      body := jsonb_build_object('source', 'supabase-cron')
    );
  $$
);
