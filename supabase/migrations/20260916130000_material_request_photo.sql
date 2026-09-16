-- A photo of the broken item says more than its name, so a request may carry
-- one optional picture. It is uploaded before the request row exists, so the
-- object path starts with the requester's own app_user id rather than the
-- request id.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'material-request-photos',
  'material-request-photos',
  false,
  2097152,
  array['image/jpeg', 'image/png']
)
on conflict (id) do update
set public = false,
    file_size_limit = 2097152,
    allowed_mime_types = array['image/jpeg', 'image/png'];

alter table public.material_request
  add column if not exists photo_path text,
  add column if not exists photo_mime text;

alter table public.material_request
  drop constraint if exists material_request_photo_check;

alter table public.material_request
  add constraint material_request_photo_check
  check (
    (photo_path is null and photo_mime is null)
    or (
      length(trim(photo_path)) > 0
      and photo_mime in ('image/jpeg', 'image/png')
    )
  );

-- The photo follows the request it belongs to: the requester sees their own,
-- and whoever may process requests sees all of them.
drop policy if exists material_request_photo_read_scoped on storage.objects;
create policy material_request_photo_read_scoped
on storage.objects
for select to authenticated
using (
  bucket_id = 'material-request-photos'
  and (
    (storage.foldername(name))[1] = public.current_sicatat_user_id()::text
    or public.can_manage_material_request()
  )
);

drop policy if exists material_request_photo_insert_own on storage.objects;
create policy material_request_photo_insert_own
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'material-request-photos'
  and (storage.foldername(name))[1] = public.current_sicatat_user_id()::text
);

-- Only the uploader may remove a picture, so a mis-picked photo can be
-- replaced before the request is sent.
drop policy if exists material_request_photo_delete_own on storage.objects;
create policy material_request_photo_delete_own
on storage.objects
for delete to authenticated
using (
  bucket_id = 'material-request-photos'
  and (storage.foldername(name))[1] = public.current_sicatat_user_id()::text
);
