-- Authenticated release channel for SICATAT Android APK updates. APK files are
-- private: the mobile app obtains a short-lived signed URL only after login.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'app-releases',
  'app-releases',
  false,
  104857600,
  array[
    'application/vnd.android.package-archive',
    'application/octet-stream'
  ]
)
on conflict (id) do update
set public = false,
    file_size_limit = 104857600,
    allowed_mime_types = array[
      'application/vnd.android.package-archive',
      'application/octet-stream'
    ];

create table if not exists public.app_release (
  id uuid primary key default gen_random_uuid(),
  platform text not null default 'android'
    check (platform in ('android')),
  version_name text not null
    check (version_name ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  version_code integer not null check (version_code > 0),
  apk_path text not null check (length(trim(apk_path)) > 0),
  release_notes text not null default '',
  is_active boolean not null default true,
  published_at timestamptz not null default now(),
  created_by uuid references public.app_user(id),
  unique (platform, version_code),
  unique (platform, version_name)
);

create index if not exists idx_app_release_latest_android
  on public.app_release (platform, is_active, version_code desc, published_at desc);

create or replace function public.stamp_app_release_creator()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.created_by is null then
    new.created_by := public.current_sicatat_user_id();
  end if;
  if new.created_by is null then
    raise exception 'An authenticated SICATAT admin is required.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_stamp_app_release_creator on public.app_release;
create trigger trg_stamp_app_release_creator
before insert on public.app_release
for each row execute function public.stamp_app_release_creator();

alter table public.app_release enable row level security;

drop policy if exists app_release_read_active on public.app_release;
create policy app_release_read_active
on public.app_release
for select to authenticated
using (is_active = true);

drop policy if exists app_release_manage_admin on public.app_release;
create policy app_release_manage_admin
on public.app_release
for all to authenticated
using (public.current_sicatat_role() = 'admin')
with check (public.current_sicatat_role() = 'admin');

drop policy if exists app_release_object_read_authenticated on storage.objects;
create policy app_release_object_read_authenticated
on storage.objects
for select to authenticated
using (bucket_id = 'app-releases');

drop policy if exists app_release_object_manage_admin on storage.objects;
create policy app_release_object_manage_admin
on storage.objects
for all to authenticated
using (
  bucket_id = 'app-releases'
  and public.current_sicatat_role() = 'admin'
)
with check (
  bucket_id = 'app-releases'
  and public.current_sicatat_role() = 'admin'
);
