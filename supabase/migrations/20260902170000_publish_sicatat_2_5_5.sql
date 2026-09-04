-- Publish v2.5.5 after the matching APKs are present in app-releases.
-- The in-app updater selects the correct ABI row for each Android device.

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
      '2.5.5',
      12255,
      'android/arm64-v8a/app-arm64-v8a-release.apk',
      E'• Bottom navigation remains available when opening Temperature, Reminders, Warehouse, and Profile.\n• Site Scope now lists only Asamasam, Kintap, Satui, Batulicin, NPLCT, and Senakin.',
      true,
      release_creator
    ),
    (
      'android',
      'armeabi-v7a',
      '2.5.5',
      11255,
      'android/armeabi-v7a/app-armeabi-v7a-release (1).apk',
      E'• Bottom navigation remains available when opening Temperature, Reminders, Warehouse, and Profile.\n• Site Scope now lists only Asamasam, Kintap, Satui, Batulicin, NPLCT, and Senakin.',
      true,
      release_creator
    ),
    (
      'android',
      'x86_64',
      '2.5.5',
      14255,
      'android/x86_64/app-x86_64-release (1).apk',
      E'• Bottom navigation remains available when opening Temperature, Reminders, Warehouse, and Profile.\n• Site Scope now lists only Asamasam, Kintap, Satui, Batulicin, NPLCT, and Senakin.',
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
