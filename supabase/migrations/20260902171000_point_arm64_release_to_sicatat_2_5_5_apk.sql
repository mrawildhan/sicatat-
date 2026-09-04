-- The pre-existing ARM64 filename remains for the prior release.
-- Point v2.5.5 to its uniquely named, verified APK object.

update public.app_release
set apk_path = 'android/arm64-v8a/app-arm64-v8a-2.5.5-release.apk',
    published_at = now()
where platform = 'android'
  and abi = 'arm64-v8a'
  and version_code = 12255;
