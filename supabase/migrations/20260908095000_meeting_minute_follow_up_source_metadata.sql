-- Simpan label MOM asal bersama tindak lanjut agar riwayat dan ekspor Excel
-- tidak bergantung pada self-join API saat daftar MOM dibuka.
alter table public.meeting_minute
  add column if not exists follow_up_source_title text not null default '',
  add column if not exists follow_up_source_date date;
