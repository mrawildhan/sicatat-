-- Publish SICATAT 2.5.8: compact home dashboard and self-service password changes.
do $$
declare
  release_creator uuid;
begin
  select id
    into release_creator
  from public.app_user
  where role = 'admin'
    and is_active = true
  order by created_at
  limit 1;

  if release_creator is null then
    raise exception 'An active admin is required to publish an app release.';
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
      '2.5.8',
      12258,
      'arm64-v8a/app-arm64-v8a-2.5.8-release.apk',
      E'• Home is now a compact daily summary with clear menu cards.\n• You can change your own password from Profile. Changing it signs out all devices for account security.\n• The login screen now supports strong passwords using letters and numbers.',
      true,
      release_creator
    ),
    (
      'android',
      'armeabi-v7a',
      '2.5.8',
      11258,
      'arm64-v8a/app-armeabi-v7a-2.5.8-release.apk',
      E'• Home is now a compact daily summary with clear menu cards.\n• You can change your own password from Profile. Changing it signs out all devices for account security.\n• The login screen now supports strong passwords using letters and numbers.',
      true,
      release_creator
    ),
    (
      'android',
      'x86_64',
      '2.5.8',
      14258,
      'arm64-v8a/app-x86_64-2.5.8-release.apk',
      E'• Home is now a compact daily summary with clear menu cards.\n• You can change your own password from Profile. Changing it signs out all devices for account security.\n• The login screen now supports strong passwords using letters and numbers.',
      true,
      release_creator
    )
  on conflict (platform, abi, version_code) do update
  set version_name = excluded.version_name,
      apk_path = excluded.apk_path,
      release_notes = excluded.release_notes,
      is_active = excluded.is_active,
      created_by = excluded.created_by;
end $$;
