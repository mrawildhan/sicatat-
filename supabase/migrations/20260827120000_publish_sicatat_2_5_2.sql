-- Publish v2.5.2 only after all ABI-specific APK files are in the private
-- app-releases bucket. The in-app updater selects the matching ABI row.

do $$
declare
  release_creator uuid;
begin
  select id
    into release_creator
  from public.app_user
  where role = 'admin'
    and is_active = true
  order by nik
  limit 1;

  if release_creator is null then
    raise exception 'An active SICATAT admin is required to publish app releases.';
  end if;

  insert into public.app_release (
    platform,
    abi,
    version_name,
    version_code,
    apk_path,
    release_notes,
    is_active,
    created_by
  )
  values
    (
      'android',
      'arm64-v8a',
      '2.5.2',
      12252,
      'android/arm64-v8a/sicatat-v2.5.2.apk',
      E'• Search reminders live by title, asset, category, location, description, or responsible person.\n• See a clear What’s new section before installing an app update.\n• Keep using site and due-date filters together with search.',
      true,
      release_creator
    ),
    (
      'android',
      'armeabi-v7a',
      '2.5.2',
      11252,
      'android/armeabi-v7a/sicatat-v2.5.2.apk',
      E'• Search reminders live by title, asset, category, location, description, or responsible person.\n• See a clear What’s new section before installing an app update.\n• Keep using site and due-date filters together with search.',
      true,
      release_creator
    ),
    (
      'android',
      'x86_64',
      '2.5.2',
      14252,
      'android/x86_64/sicatat-v2.5.2.apk',
      E'• Search reminders live by title, asset, category, location, description, or responsible person.\n• See a clear What’s new section before installing an app update.\n• Keep using site and due-date filters together with search.',
      true,
      release_creator
    )
  on conflict (platform, abi, version_code) do update
  set apk_path = excluded.apk_path,
      release_notes = excluded.release_notes,
      is_active = true,
      published_at = now();
end;
$$;
