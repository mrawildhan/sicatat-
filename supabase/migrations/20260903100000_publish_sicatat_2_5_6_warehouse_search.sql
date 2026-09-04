-- Publish the Warehouse search and detail-sheet experience for all Android ABIs.

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
    platform, abi, version_name, version_code, apk_path, release_notes, is_active, created_by
  )
  values
    (
      'android', 'arm64-v8a', '2.5.6', 12256,
      'android/arm64-v8a/app-arm64-v8a-2.5.6-release.apk',
      E'• Warehouse now starts with search, so stock is shown only after you search.\n• Ask Warehouse and the sync-count banner were removed.\n• Tap an item to view all available Google Sheet fields.',
      true, release_creator
    ),
    (
      'android', 'armeabi-v7a', '2.5.6', 11256,
      'android/armeabi-v7a/app-armeabi-v7a-2.5.6-release.apk',
      E'• Warehouse now starts with search, so stock is shown only after you search.\n• Ask Warehouse and the sync-count banner were removed.\n• Tap an item to view all available Google Sheet fields.',
      true, release_creator
    ),
    (
      'android', 'x86_64', '2.5.6', 14256,
      'android/armeabi-v7a/app-x86_64-2.5.6-release.apk',
      E'• Warehouse now starts with search, so stock is shown only after you search.\n• Ask Warehouse and the sync-count banner were removed.\n• Tap an item to view all available Google Sheet fields.',
      true, release_creator
    )
  on conflict (platform, abi, version_code) do update
  set apk_path = excluded.apk_path,
      release_notes = excluded.release_notes,
      is_active = true,
      published_at = now();
end;
$$;
