-- Tindak lanjut minggu berikutnya adalah notulen baru agar MOM yang telah
-- selesai tidak kehilangan riwayat. Baris ini menunjuk MOM asalnya.
alter table public.meeting_minute
  add column if not exists follow_up_of uuid;

alter table public.meeting_minute
  drop constraint if exists meeting_minute_follow_up_of_fkey;

alter table public.meeting_minute
  add constraint meeting_minute_follow_up_of_fkey
  foreign key (follow_up_of) references public.meeting_minute(id)
  on delete set null;

create index if not exists meeting_minute_follow_up_of_idx
  on public.meeting_minute(follow_up_of);
