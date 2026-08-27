-- A completed reminder is an auditable operational action: it requires one or
-- more proof files and creates the next cycle atomically when recurrence is set.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'reminder-evidence',
  'reminder-evidence',
  false,
  10485760,
  array['application/pdf', 'image/jpeg', 'image/png']
)
on conflict (id) do update
set public = false,
    file_size_limit = 10485760,
    allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png'];

create table if not exists public.operational_reminder_evidence (
  id uuid primary key default gen_random_uuid(),
  reminder_id uuid not null references public.operational_reminder(id) on delete cascade,
  file_name text not null check (length(trim(file_name)) > 0),
  storage_path text not null unique check (length(trim(storage_path)) > 0),
  mime_type text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png')),
  size_bytes integer not null check (size_bytes between 1 and 10485760),
  uploaded_by uuid not null references public.app_user(id),
  uploaded_at timestamptz not null default now()
);

create index if not exists idx_operational_reminder_evidence_reminder
  on public.operational_reminder_evidence (reminder_id, uploaded_at);

create unique index if not exists uq_operational_reminder_next_cycle
  on public.operational_reminder (parent_reminder_id)
  where parent_reminder_id is not null;

alter table public.operational_reminder_evidence enable row level security;

drop policy if exists operational_reminder_evidence_read_scoped on public.operational_reminder_evidence;
create policy operational_reminder_evidence_read_scoped
on public.operational_reminder_evidence
for select to authenticated
using (
  exists (
    select 1
    from public.operational_reminder reminder
    where reminder.id = reminder_id
      and public.can_manage_sicatat_reminder_site(reminder.site_id)
  )
);

drop policy if exists reminder_evidence_object_read_scoped on storage.objects;
create policy reminder_evidence_object_read_scoped
on storage.objects
for select to authenticated
using (
  bucket_id = 'reminder-evidence'
  and exists (
    select 1
    from public.operational_reminder reminder
    where reminder.id::text = (storage.foldername(name))[1]
      and public.can_manage_sicatat_reminder_site(reminder.site_id)
  )
);

drop policy if exists reminder_evidence_object_insert_scoped on storage.objects;
create policy reminder_evidence_object_insert_scoped
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'reminder-evidence'
  and exists (
    select 1
    from public.operational_reminder reminder
    where reminder.id::text = (storage.foldername(name))[1]
      and reminder.status = 'open'
      and public.can_manage_sicatat_reminder_site(reminder.site_id)
  )
);

drop policy if exists reminder_evidence_object_delete_scoped on storage.objects;
create policy reminder_evidence_object_delete_scoped
on storage.objects
for delete to authenticated
using (
  bucket_id = 'reminder-evidence'
  and exists (
    select 1
    from public.operational_reminder reminder
    where reminder.id::text = (storage.foldername(name))[1]
      and reminder.status = 'open'
      and public.can_manage_sicatat_reminder_site(reminder.site_id)
  )
);

create or replace function public.complete_operational_reminder(
  p_reminder_id uuid,
  p_completed_note text default null,
  p_evidence jsonb default '[]'::jsonb
)
returns table (next_reminder_id uuid, next_due_date date)
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  reminder public.operational_reminder%rowtype;
  actor_id uuid;
  proof jsonb;
  proof_path text;
  proof_name text;
  proof_mime text;
  proof_size integer;
  next_id uuid;
  next_date date;
begin
  select public.current_sicatat_user_id() into actor_id;
  if actor_id is null then
    raise exception 'No active SICATAT user.' using errcode = '42501';
  end if;
  if jsonb_typeof(p_evidence) <> 'array'
     or jsonb_array_length(p_evidence) not between 1 and 5 then
    raise exception 'Attach from one to five proof files before completing this reminder.' using errcode = '22023';
  end if;

  select * into reminder
  from public.operational_reminder
  where id = p_reminder_id
  for update;
  if not found then
    raise exception 'Reminder was not found.' using errcode = 'P0002';
  end if;
  if not public.can_manage_sicatat_reminder_site(reminder.site_id) then
    raise exception 'This reminder is outside your access scope.' using errcode = '42501';
  end if;
  if reminder.status <> 'open' then
    raise exception 'Only open reminders can be completed.' using errcode = 'P0001';
  end if;

  for proof in select value from jsonb_array_elements(p_evidence) loop
    proof_path := trim(coalesce(proof ->> 'storage_path', ''));
    proof_name := trim(coalesce(proof ->> 'file_name', ''));
    proof_mime := trim(coalesce(proof ->> 'mime_type', ''));
    proof_size := nullif(proof ->> 'size_bytes', '')::integer;
    if proof_path not like p_reminder_id::text || '/%'
       or proof_name !~* '\.(pdf|jpe?g|png)$'
       or proof_mime not in ('application/pdf', 'image/jpeg', 'image/png')
       or proof_size not between 1 and 10485760 then
      raise exception 'One or more evidence files are invalid.' using errcode = '22023';
    end if;
    if not exists (
      select 1
      from storage.objects
      where bucket_id = 'reminder-evidence'
        and name = proof_path
    ) then
      raise exception 'Uploaded evidence file was not found.' using errcode = 'P0002';
    end if;
  end loop;

  update public.operational_reminder
  set status = 'completed',
      completed_at = now(),
      completed_note = nullif(trim(p_completed_note), '')
  where id = reminder.id;

  for proof in select value from jsonb_array_elements(p_evidence) loop
    insert into public.operational_reminder_evidence (
      reminder_id, file_name, storage_path, mime_type, size_bytes, uploaded_by
    ) values (
      reminder.id,
      trim(proof ->> 'file_name'),
      trim(proof ->> 'storage_path'),
      trim(proof ->> 'mime_type'),
      (proof ->> 'size_bytes')::integer,
      actor_id
    );
  end loop;

  if reminder.recurrence_months is not null then
    next_date := (reminder.due_date + make_interval(months => reminder.recurrence_months))::date;
    insert into public.operational_reminder (
      site_id, title, due_date, recipient_emails, category, asset_code,
      description, priority, assigned_to, location, reminder_offsets_days,
      reminder_schedule, custom_reminder_days, recurrence_months,
      parent_reminder_id, created_by
    ) values (
      reminder.site_id, reminder.title, next_date, reminder.recipient_emails,
      reminder.category, reminder.asset_code, reminder.description,
      reminder.priority, reminder.assigned_to, reminder.location,
      reminder.reminder_offsets_days, reminder.reminder_schedule,
      reminder.custom_reminder_days, reminder.recurrence_months,
      reminder.id, actor_id
    )
    on conflict (parent_reminder_id) where parent_reminder_id is not null do nothing
    returning id into next_id;

    if next_id is null then
      select id into next_id
      from public.operational_reminder
      where parent_reminder_id = reminder.id;
    end if;
  end if;

  insert into public.operational_reminder_activity (
    reminder_id, action, note, details, actor_id
  ) values (
    reminder.id,
    'evidence_uploaded',
    'Completion proof uploaded.',
    jsonb_build_object('file_count', jsonb_array_length(p_evidence)),
    actor_id
  );

  return query select next_id, next_date;
end;
$$;

grant execute on function public.complete_operational_reminder(uuid, text, jsonb)
  to authenticated;
