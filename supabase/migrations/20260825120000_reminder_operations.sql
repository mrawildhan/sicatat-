-- Expand operational reminders from a simple due-date list into an auditable
-- work-management feature. Existing rows are preserved and receive safe defaults.

alter table public.operational_reminder
  add column if not exists category text not null default 'General',
  add column if not exists asset_code text,
  add column if not exists description text,
  add column if not exists priority text not null default 'normal',
  add column if not exists assigned_to text,
  add column if not exists location text,
  add column if not exists status text not null default 'open',
  add column if not exists reminder_offsets_days integer[] not null default array[30, 14, 7, 1, 0],
  add column if not exists recurrence_months integer,
  add column if not exists parent_reminder_id uuid references public.operational_reminder(id),
  add column if not exists completed_at timestamptz,
  add column if not exists completed_note text,
  add column if not exists updated_by uuid references public.app_user(id),
  add column if not exists last_sent_at timestamptz;

alter table public.operational_reminder
  drop constraint if exists operational_reminder_priority_check,
  add constraint operational_reminder_priority_check
    check (priority in ('low', 'normal', 'high', 'critical')),
  drop constraint if exists operational_reminder_status_check,
  add constraint operational_reminder_status_check
    check (status in ('open', 'completed', 'cancelled')),
  drop constraint if exists operational_reminder_recurrence_months_check,
  add constraint operational_reminder_recurrence_months_check
    check (recurrence_months is null or recurrence_months in (1, 3, 6, 12)),
  drop constraint if exists operational_reminder_reminder_offsets_days_check,
  add constraint operational_reminder_reminder_offsets_days_check
    check (
      cardinality(reminder_offsets_days) > 0
      and reminder_offsets_days <@ array[30, 14, 7, 1, 0]
    );

create index if not exists idx_operational_reminder_status_due_date
  on public.operational_reminder (status, due_date);

create index if not exists idx_operational_reminder_category
  on public.operational_reminder (category);

create table if not exists public.operational_reminder_delivery (
  id uuid primary key default gen_random_uuid(),
  reminder_id uuid not null references public.operational_reminder(id) on delete cascade,
  delivery_type text not null check (delivery_type in ('manual', 'scheduled')),
  scheduled_offset_days integer,
  due_date_snapshot date not null,
  recipients text[] not null,
  provider_id text,
  status text not null default 'sending' check (status in ('sending', 'sent', 'failed')),
  error_message text,
  sent_by uuid references public.app_user(id),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_scheduled_reminder_delivery
  on public.operational_reminder_delivery (
    reminder_id,
    due_date_snapshot,
    scheduled_offset_days
  )
  where delivery_type = 'scheduled';

create index if not exists idx_reminder_delivery_history
  on public.operational_reminder_delivery (reminder_id, created_at desc);

create table if not exists public.operational_reminder_activity (
  id uuid primary key default gen_random_uuid(),
  reminder_id uuid not null references public.operational_reminder(id) on delete cascade,
  action text not null,
  note text,
  details jsonb not null default '{}'::jsonb,
  actor_id uuid references public.app_user(id),
  occurred_at timestamptz not null default now()
);

create index if not exists idx_reminder_activity_history
  on public.operational_reminder_activity (reminder_id, occurred_at desc);

create or replace function public.touch_operational_reminder()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select id into new.updated_by
  from public.app_user
  where nik = split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1)
  limit 1;
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.log_operational_reminder_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  activity_action text;
  activity_note text;
begin
  if tg_op = 'INSERT' then
    activity_action := 'created';
  elsif new.status = 'completed' and old.status <> 'completed' then
    activity_action := 'completed';
    activity_note := new.completed_note;
  elsif old.status = 'completed' and new.status = 'open' then
    activity_action := 'reopened';
  elsif new.status = 'cancelled' and old.status <> 'cancelled' then
    activity_action := 'cancelled';
  elsif new.due_date <> old.due_date then
    activity_action := 'rescheduled';
    activity_note := 'Due date changed from ' || old.due_date || ' to ' || new.due_date || '.';
  else
    activity_action := 'updated';
  end if;

  insert into public.operational_reminder_activity (
    reminder_id,
    action,
    note,
    details,
    actor_id
  ) values (
    new.id,
    activity_action,
    activity_note,
    jsonb_build_object(
      'status', new.status,
      'priority', new.priority,
      'due_date', new.due_date,
      'category', new.category
    ),
    coalesce(new.updated_by, new.created_by)
  );
  return new;
end;
$$;

create or replace function public.touch_operational_reminder_delivery()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_log_operational_reminder_activity on public.operational_reminder;
create trigger trg_log_operational_reminder_activity
after insert or update on public.operational_reminder
for each row execute function public.log_operational_reminder_activity();

drop trigger if exists trg_touch_operational_reminder_delivery on public.operational_reminder_delivery;
create trigger trg_touch_operational_reminder_delivery
before update on public.operational_reminder_delivery
for each row execute function public.touch_operational_reminder_delivery();

alter table public.operational_reminder_delivery enable row level security;
alter table public.operational_reminder_activity enable row level security;

drop policy if exists operational_reminder_delivery_admin_only on public.operational_reminder_delivery;
create policy operational_reminder_delivery_admin_only
on public.operational_reminder_delivery
for all
to authenticated
using (public.is_active_sicatat_admin())
with check (public.is_active_sicatat_admin());

drop policy if exists operational_reminder_activity_admin_only on public.operational_reminder_activity;
create policy operational_reminder_activity_admin_only
on public.operational_reminder_activity
for all
to authenticated
using (public.is_active_sicatat_admin())
with check (public.is_active_sicatat_admin());

-- Supabase Cron runs daily at 08:00 WITA (00:00 UTC). The schedule reads its
-- private header value from Vault at run time. The secret itself is installed
-- after this migration and is never committed to Git.
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.unschedule(jobid)
from cron.job
where jobname = 'sicatat-dispatch-operational-reminders';

select cron.schedule(
  'sicatat-dispatch-operational-reminders',
  '0 0 * * *',
  $$
    select net.http_post(
      url := 'https://ofczleeyqrxyuuupzirq.supabase.co/functions/v1/dispatch-reminder-emails',
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
