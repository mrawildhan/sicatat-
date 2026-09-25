-- Unggah data: an admin uploads a spreadsheet straight into SICATAT instead of
-- keeping it on a public Google Drive link (owner request 2026-09-25).
--
-- A file is uploaded to incoming/<part> first. The matching sync function
-- imports it and only on success moves it to current/<part>, so a broken file
-- never replaces a working one. While current/<part> exists that part is read
-- from here and its Drive link is ignored; deleting it falls back to Drive.
-- Only the latest file per part is kept (about 8 MB in total).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'data-source-uploads',
  'data-source-uploads',
  false,
  15728640,
  array[
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel.sheet.macroEnabled.12',
    'application/octet-stream'
  ]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists data_source_upload_incoming_write on storage.objects;
create policy data_source_upload_incoming_write
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'data-source-uploads'
  and (storage.foldername(name))[1] = 'incoming'
  and public.is_active_sicatat_admin()
);

drop policy if exists data_source_upload_incoming_update on storage.objects;
create policy data_source_upload_incoming_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'data-source-uploads'
  and (storage.foldername(name))[1] = 'incoming'
  and public.is_active_sicatat_admin()
)
with check (
  bucket_id = 'data-source-uploads'
  and (storage.foldername(name))[1] = 'incoming'
  and public.is_active_sicatat_admin()
);

-- Upsert needs to see the object it overwrites.
drop policy if exists data_source_upload_admin_read on storage.objects;
create policy data_source_upload_admin_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'data-source-uploads'
  and public.is_active_sicatat_admin()
);

-- "Kembali ke Drive" removes the stored file.
drop policy if exists data_source_upload_admin_delete on storage.objects;
create policy data_source_upload_admin_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'data-source-uploads'
  and public.is_active_sicatat_admin()
);

create table if not exists public.data_source_upload (
  part text primary key,
  source text not null,
  file_name text not null,
  size_bytes integer not null default 0,
  uploaded_at timestamptz not null default now(),
  uploaded_by uuid references public.app_user(id) on delete set null
);

alter table public.data_source_upload enable row level security;

drop policy if exists data_source_upload_admin_read on public.data_source_upload;
create policy data_source_upload_admin_read
on public.data_source_upload
for select
to authenticated
using (public.is_active_sicatat_admin());

drop policy if exists data_source_upload_admin_delete on public.data_source_upload;
create policy data_source_upload_admin_delete
on public.data_source_upload
for delete
to authenticated
using (public.is_active_sicatat_admin());

grant select, delete on public.data_source_upload to authenticated;
