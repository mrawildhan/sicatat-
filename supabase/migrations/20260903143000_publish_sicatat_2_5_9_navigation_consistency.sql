-- Publish SICATAT 2.5.9: persistent navigation across all operational sheets.
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
      '2.5.9',
      12259,
      'arm64-v8a/app-arm64-v8a-2.5.9-release.apk',
      E'• Navigation is now retained across incomplete sheets, monitoring, temperature entry, summaries, reports, exports, and guides.\n• Incomplete and monitored sheet cards can be tapped anywhere to open the relevant temperature sheet or its safe summary.\n• Desktop and mobile navigation use the same layout rules.',
      true,
      release_creator
    ),
    (
      'android',
      'armeabi-v7a',
      '2.5.9',
      11259,
      'armeabi-v7a/app-armeabi-v7a-2.5.9-release.apk',
      E'• Navigation is now retained across incomplete sheets, monitoring, temperature entry, summaries, reports, exports, and guides.\n• Incomplete and monitored sheet cards can be tapped anywhere to open the relevant temperature sheet or its safe summary.\n• Desktop and mobile navigation use the same layout rules.',
      true,
      release_creator
    ),
    (
      'android',
      'x86_64',
      '2.5.9',
      14259,
      'x86_64/app-x86_64-2.5.9-release.apk',
      E'• Navigation is now retained across incomplete sheets, monitoring, temperature entry, summaries, reports, exports, and guides.\n• Incomplete and monitored sheet cards can be tapped anywhere to open the relevant temperature sheet or its safe summary.\n• Desktop and mobile navigation use the same layout rules.',
      true,
      release_creator
    )
  on conflict (platform, abi, version_code) do update
  set version_name = excluded.version_name,
      apk_path = excluded.apk_path,
      release_notes = excluded.release_notes,
      is_active = excluded.is_active,
      created_by = excluded.created_by,
      published_at = now();
end $$;
