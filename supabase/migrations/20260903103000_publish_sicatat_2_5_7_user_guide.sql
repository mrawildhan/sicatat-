-- Publish SICATAT 2.5.7 with the updated in-app user guide.
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
      '2.5.7',
      12257,
      'arm64-v8a/app-arm64-v8a-release (1).apk',
      E'• User guide now explains Warehouse search, item details, and Android updates.\n• Warehouse information is shown after searching, then an item can be opened for its Google Sheet details.',
      true,
      release_creator
    ),
    (
      'android',
      'armeabi-v7a',
      '2.5.7',
      11257,
      'arm64-v8a/app-armeabi-v7a-2.5.7-release.apk',
      E'• User guide now explains Warehouse search, item details, and Android updates.\n• Warehouse information is shown after searching, then an item can be opened for its Google Sheet details.',
      true,
      release_creator
    ),
    (
      'android',
      'x86_64',
      '2.5.7',
      14257,
      'arm64-v8a/app-x86_64-2.5.7-release.apk',
      E'• User guide now explains Warehouse search, item details, and Android updates.\n• Warehouse information is shown after searching, then an item can be opened for its Google Sheet details.',
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
