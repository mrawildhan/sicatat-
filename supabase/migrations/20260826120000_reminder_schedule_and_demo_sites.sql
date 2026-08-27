-- Reminder timing is intentionally a single, predictable automatic email:
-- weekly = seven days before, monthly = one calendar month before, and custom
-- = the operator-selected number of days before the due date.

alter table public.operational_reminder
  add column if not exists reminder_schedule text,
  add column if not exists custom_reminder_days integer;

alter table public.operational_reminder
  drop constraint if exists operational_reminder_schedule_check,
  add constraint operational_reminder_schedule_check
    check (
      reminder_schedule is null
      or (
        reminder_schedule in ('weekly', 'monthly', 'custom')
        and (
          (reminder_schedule = 'custom'
            and custom_reminder_days between 0 and 365)
          or (reminder_schedule in ('weekly', 'monthly')
            and custom_reminder_days is null)
        )
      )
    );

alter table public.operational_reminder_delivery
  add column if not exists scheduled_schedule_type text;

alter table public.operational_reminder_delivery
  drop constraint if exists operational_reminder_delivery_schedule_type_check,
  add constraint operational_reminder_delivery_schedule_type_check
    check (
      scheduled_schedule_type is null
      or scheduled_schedule_type in ('weekly', 'monthly', 'custom', 'legacy')
    );

-- Keep the master site list complete and idempotent. Existing references use
-- the stable code, so updating a display name does not disturb site-scoped data.
insert into public.site (code, name)
values
  ('ASAMASAM', 'Asamasam'),
  ('KINTAP', 'Kintap'),
  ('SATUI', 'Satui'),
  ('BATULICIN', 'Batulicin'),
  ('SENAKIN', 'Senakin'),
  ('NPLCT', 'NPLCT'),
  ('LQ', 'LQ'),
  ('BANJARMASIN', 'Banjarmasin'),
  ('DRILLING', 'Drilling'),
  ('PROJECT', 'Project'),
  ('JAKARTA', 'Jakarta'),
  ('RDAS', 'RDAS')
on conflict (code) do update
set name = excluded.name,
    is_active = true;

-- One test reminder per active site. The three schedules are rotated so a
-- deployment can be exercised immediately with a manual send and on the next
-- daily cron run. The seed is skipped only when the project has no active user
-- available to own audit records.
do $$
declare
  seed_actor_id uuid;
  site_row record;
  site_number integer := 0;
  selected_schedule text;
  selected_custom_days integer;
  selected_due_date date;
  demo_title text;
begin
  select id
  into seed_actor_id
  from public.app_user
  where is_active = true
  order by case when role = 'admin' then 0 else 1 end, created_at
  limit 1;

  if seed_actor_id is null then
    raise notice 'Reminder demo data skipped: no active SICATAT user exists yet.';
    return;
  end if;

  for site_row in
    select id, code, name
    from public.site
    where code in (
      'ASAMASAM', 'KINTAP', 'SATUI', 'BATULICIN', 'SENAKIN', 'NPLCT',
      'LQ', 'BANJARMASIN', 'DRILLING', 'PROJECT', 'JAKARTA', 'RDAS'
    )
    order by code
  loop
    site_number := site_number + 1;
    selected_schedule := case site_number % 3
      when 1 then 'weekly'
      when 2 then 'monthly'
      else 'custom'
    end;
    selected_custom_days := case when selected_schedule = 'custom'
      then 3 + (site_number % 5)
      else null
    end;
    selected_due_date := case selected_schedule
      when 'weekly' then current_date + 7
      when 'monthly' then (current_date + interval '1 month')::date
      else current_date + selected_custom_days
    end;
    demo_title := '[DEMO] Permit renewal - ' || site_row.name;

    if not exists (
      select 1
      from public.operational_reminder
      where site_id = site_row.id
        and title = demo_title
    ) then
      insert into public.operational_reminder (
        site_id,
        title,
        due_date,
        recipient_emails,
        category,
        asset_code,
        description,
        priority,
        assigned_to,
        location,
        status,
        reminder_schedule,
        custom_reminder_days,
        created_by
      ) values (
        site_row.id,
        demo_title,
        selected_due_date,
        array['mcasamasam@arutmin.com'],
        'Vehicle document',
        'SMG-' || lpad(site_number::text, 3, '0'),
        'Demo reminder to verify the ' || selected_schedule || ' email schedule.',
        case when selected_schedule = 'custom' then 'high' else 'normal' end,
        'SICATAT Reminder Test',
        site_row.name,
        'open',
        selected_schedule,
        selected_custom_days,
        seed_actor_id
      );
    end if;
  end loop;
end;
$$;
