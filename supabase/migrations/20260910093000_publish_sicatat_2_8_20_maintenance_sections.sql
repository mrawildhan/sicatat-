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
    raise exception 'Tidak ada akun admin aktif untuk menerbitkan rilis aplikasi.';
  end if;

  update public.app_release
     set is_active = false
   where platform = 'android'
     and abi = 'arm64-v8a';

  insert into public.app_release (
    platform,
    abi,
    version_name,
    version_code,
    apk_path,
    release_notes,
    is_active,
    created_by
  ) values (
    'android',
    'arm64-v8a',
    '2.8.20',
    12300,
    'arm64-v8a/app-arm64-v8a-2.8.20-release.apk',
    E'• Ringkasan Outstanding kini berupa kartu PM dan CM yang lebih jelas.\n• Ketuk kartu untuk membuka daftar layar penuh dan mencari work order.',
    true,
    release_creator
  );
end
$$;
