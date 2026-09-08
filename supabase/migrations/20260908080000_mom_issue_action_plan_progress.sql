-- Menyimpan isu, action plan, dan progress/remark terpisah agar satu isu
-- dapat memiliki beberapa action plan pada tabel MOM dan ekspor Excel.

alter table public.meeting_minute_action
  add column if not exists issue_description text not null default '',
  add column if not exists progress_remark text not null default '';

-- Tindakan lama tetap terbaca sebagai satu isu dengan action plan yang sama.
update public.meeting_minute_action
set issue_description = subject_discussion
where trim(issue_description) = '';

-- Action plan dapat memiliki maksimal dua foto bukti opsional. Mengganti
-- aturan satu foto dari rilis sebelumnya tanpa menghapus foto lama.
create or replace function public.enforce_single_meeting_minute_action_photo()
returns trigger
language plpgsql
as $$
begin
  perform pg_advisory_xact_lock(hashtext(new.meeting_minute_action_id::text));

  if (
    select count(*)
    from public.meeting_minute_action_photo
    where meeting_minute_action_id = new.meeting_minute_action_id
  ) >= 2 then
    raise exception 'Setiap action plan maksimal dapat memiliki dua foto.'
      using errcode = '23505';
  end if;

  return new;
end;
$$;
