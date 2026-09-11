-- Distribusi Android saat ini difokuskan ke arm64-v8a.
-- Catatan rilis lama tetap tersimpan sebagai riwayat, tetapi tidak boleh
-- mengarahkan perangkat ABI lain ke APK yang telah dibersihkan dari Storage.
update public.app_release
set is_active = false
where platform = 'android'
  and abi in ('armeabi-v7a', 'x86_64');
