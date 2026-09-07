-- Foto bersifat opsional untuk tiap pembahasan/tindak lanjut MOM. Berkas
-- disimpan privat agar hanya pengguna dengan cakupan notulen yang sama yang
-- dapat melihat atau mengunduhnya.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'meeting-minute-photos',
  'meeting-minute-photos',
  false,
  8388608,
  array['image/jpeg', 'image/png']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.meeting_minute_action_photo (
  id uuid primary key default gen_random_uuid(),
  meeting_minute_action_id uuid not null references public.meeting_minute_action(id)
    on delete cascade,
  storage_path text not null unique,
  file_name text not null default 'Foto pembahasan',
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png')),
  size_bytes integer not null check (size_bytes > 0 and size_bytes <= 8388608),
  position integer not null default 0 check (position >= 0),
  uploaded_at timestamptz not null default now()
);

create index if not exists meeting_minute_action_photo_parent_position_idx
  on public.meeting_minute_action_photo(meeting_minute_action_id, position);

alter table public.meeting_minute_action_photo enable row level security;

drop policy if exists meeting_minute_action_photo_read_scoped on public.meeting_minute_action_photo;
create policy meeting_minute_action_photo_read_scoped on public.meeting_minute_action_photo
for select to authenticated
using (
  exists (
    select 1
    from public.meeting_minute_action a
    join public.meeting_minute m on m.id = a.meeting_minute_id
    where a.id = meeting_minute_action_id
      and public.can_read_meeting_minute(m.created_by)
  )
);

drop policy if exists meeting_minute_action_photo_write_scoped on public.meeting_minute_action_photo;
create policy meeting_minute_action_photo_write_scoped on public.meeting_minute_action_photo
for all to authenticated
using (
  exists (
    select 1
    from public.meeting_minute_action a
    join public.meeting_minute m on m.id = a.meeting_minute_id
    where a.id = meeting_minute_action_id
      and public.can_write_meeting_minute(m.created_by)
  )
)
with check (
  exists (
    select 1
    from public.meeting_minute_action a
    join public.meeting_minute m on m.id = a.meeting_minute_id
    where a.id = meeting_minute_action_id
      and public.can_write_meeting_minute(m.created_by)
  )
);

drop policy if exists meeting_minute_photo_storage_read on storage.objects;
create policy meeting_minute_photo_storage_read on storage.objects
for select to authenticated
using (
  bucket_id = 'meeting-minute-photos'
  and exists (
    select 1
    from public.meeting_minute_action a
    join public.meeting_minute m on m.id = a.meeting_minute_id
    where storage.objects.name like
        'meeting-minutes/' || m.id::text || '/' || a.id::text || '/%'
      and public.can_read_meeting_minute(m.created_by)
  )
);

drop policy if exists meeting_minute_photo_storage_write on storage.objects;
create policy meeting_minute_photo_storage_write on storage.objects
for all to authenticated
using (
  bucket_id = 'meeting-minute-photos'
  and exists (
    select 1
    from public.meeting_minute_action a
    join public.meeting_minute m on m.id = a.meeting_minute_id
    where storage.objects.name like
        'meeting-minutes/' || m.id::text || '/' || a.id::text || '/%'
      and public.can_write_meeting_minute(m.created_by)
  )
)
with check (
  bucket_id = 'meeting-minute-photos'
  and exists (
    select 1
    from public.meeting_minute_action a
    join public.meeting_minute m on m.id = a.meeting_minute_id
    where storage.objects.name like
        'meeting-minutes/' || m.id::text || '/' || a.id::text || '/%'
      and public.can_write_meeting_minute(m.created_by)
  )
);
