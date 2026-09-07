-- Warehouse is refreshed by the server every day at 06:00 WITA (22:00 UTC).
-- The private request secret is read from Supabase Vault at run time. Its value
-- is installed outside Git under the name sicatat_warehouse_sync_cron_secret.

alter table public.warehouse_sync_log
  add column if not exists trigger_source text not null default 'manual',
  add column if not exists changed boolean not null default false,
  add column if not exists source_fingerprint text;

alter table public.warehouse_sync_log
  drop constraint if exists warehouse_sync_log_trigger_source_check;

alter table public.warehouse_sync_log
  add constraint warehouse_sync_log_trigger_source_check
  check (trigger_source in ('manual', 'scheduled'));

create index if not exists idx_warehouse_sync_log_completed_at
  on public.warehouse_sync_log (completed_at desc)
  where status = 'completed';

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.unschedule(jobid)
from cron.job
where jobname = 'sicatat-sync-warehouse-daily';

select cron.schedule(
  'sicatat-sync-warehouse-daily',
  '0 22 * * *',
  $$
    select net.http_post(
      url := 'https://ofczleeyqrxyuuupzirq.supabase.co/functions/v1/sync-warehouse-data',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-warehouse-cron-secret', (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'sicatat_warehouse_sync_cron_secret'
        )
      ),
      body := jsonb_build_object('source', 'supabase-cron')
    );
  $$
);
