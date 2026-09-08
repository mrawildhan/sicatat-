-- Mulai rilis ini, satu pembahasan/tindak lanjut MOM memiliki maksimal satu
-- foto opsional. Data lama tidak dihapus; trigger ini hanya mencegah unggahan
-- foto tambahan untuk tindakan yang sudah mempunyai foto.

create or replace function public.enforce_single_meeting_minute_action_photo()
returns trigger
language plpgsql
as $$
begin
  -- Serialize uploads to the same action so two uploads bersamaan juga tidak
  -- dapat menghasilkan lebih dari satu foto.
  perform pg_advisory_xact_lock(hashtext(new.meeting_minute_action_id::text));

  if exists (
    select 1
    from public.meeting_minute_action_photo
    where meeting_minute_action_id = new.meeting_minute_action_id
  ) then
    raise exception 'Setiap pembahasan hanya dapat memiliki satu foto.'
      using errcode = '23505';
  end if;

  return new;
end;
$$;

drop trigger if exists meeting_minute_action_photo_single_per_action
  on public.meeting_minute_action_photo;
create trigger meeting_minute_action_photo_single_per_action
before insert on public.meeting_minute_action_photo
for each row execute function public.enforce_single_meeting_minute_action_photo();
