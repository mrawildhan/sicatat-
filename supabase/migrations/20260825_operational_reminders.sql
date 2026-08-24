-- Operational reminders are online-only shared data. The tables keep a
-- recipient snapshot on each reminder and a directory for checkbox selection.

create table if not exists public.reminder_recipient (
  id uuid primary key default gen_random_uuid(),
  email text not null unique check (email = lower(email)),
  label text not null,
  is_active boolean not null default true,
  created_by uuid references public.app_user(id),
  created_at timestamptz not null default now()
);

create table if not exists public.operational_reminder (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) > 0),
  due_date date not null,
  recipient_emails text[] not null check (cardinality(recipient_emails) > 0),
  created_by uuid references public.app_user(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_operational_reminder_due_date
  on public.operational_reminder (due_date);

-- A selectable contact, not an automatic-send target.
insert into public.reminder_recipient (email, label)
values ('mcasamasam@arutmin.com', 'mcasamasam@arutmin.com')
on conflict (email) do nothing;

create or replace function public.is_active_sicatat_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_user
    where nik = split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1)
      and role = 'admin'
      and is_active = true
  );
$$;

create or replace function public.stamp_operational_reminder_creator()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.created_by is null then
    select id into new.created_by
    from public.app_user
    where nik = split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1)
    limit 1;
  end if;
  if new.created_by is null then
    raise exception 'An authenticated SICATAT user is required.';
  end if;
  return new;
end;
$$;

create or replace function public.touch_operational_reminder()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_stamp_reminder_recipient_creator on public.reminder_recipient;
create trigger trg_stamp_reminder_recipient_creator
before insert on public.reminder_recipient
for each row execute function public.stamp_operational_reminder_creator();

drop trigger if exists trg_stamp_operational_reminder_creator on public.operational_reminder;
create trigger trg_stamp_operational_reminder_creator
before insert on public.operational_reminder
for each row execute function public.stamp_operational_reminder_creator();

drop trigger if exists trg_touch_operational_reminder on public.operational_reminder;
create trigger trg_touch_operational_reminder
before update on public.operational_reminder
for each row execute function public.touch_operational_reminder();

alter table public.reminder_recipient enable row level security;
alter table public.operational_reminder enable row level security;

drop policy if exists reminder_recipient_admin_only on public.reminder_recipient;
create policy reminder_recipient_admin_only
on public.reminder_recipient
for all
to authenticated
using (public.is_active_sicatat_admin())
with check (public.is_active_sicatat_admin());

drop policy if exists operational_reminder_admin_only on public.operational_reminder;
create policy operational_reminder_admin_only
on public.operational_reminder
for all
to authenticated
using (public.is_active_sicatat_admin())
with check (public.is_active_sicatat_admin());
