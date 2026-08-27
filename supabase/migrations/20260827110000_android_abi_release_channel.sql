-- Supabase Free projects limit individual objects to 50 MB. Publish one APK
-- per Android ABI so the update channel remains installable on every device.

update storage.buckets
set file_size_limit = 52428800
where id = 'app-releases';

alter table public.app_release
  add column if not exists abi text;

update public.app_release
set abi = 'arm64-v8a'
where abi is null;

alter table public.app_release
  alter column abi set not null,
  drop constraint if exists app_release_abi_check,
  add constraint app_release_abi_check
    check (abi in ('arm64-v8a', 'armeabi-v7a', 'x86_64'));

alter table public.app_release
  drop constraint if exists app_release_platform_version_code_key,
  drop constraint if exists app_release_platform_version_name_key,
  add constraint app_release_platform_abi_version_code_key
    unique (platform, abi, version_code),
  add constraint app_release_platform_abi_version_name_key
    unique (platform, abi, version_name);

drop index if exists public.idx_app_release_latest_android;
create index idx_app_release_latest_android
  on public.app_release (
    platform,
    abi,
    is_active,
    version_code desc,
    published_at desc
  );
