-- Indonesian error messages for the daily check sheets (the owner wants the
-- sheet contents in Indonesian; only the three menu names stay English).

create or replace function public.daily_check_sheet_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- The site always follows the team, never the client.
  select t.site_id into new.site_id from public.team t where t.id = new.team_id;
  if new.site_id is null then
    raise exception 'Regu yang dipilih belum memiliki lokasi.';
  end if;
  new.updated_at := now();
  new.updated_by := public.current_sicatat_user_id();
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.status := 'draft';
    new.submitted_at := null;
    new.submitted_by := null;
  else
    -- Identity of a sheet never changes after it is created.
    new.form_type := old.form_type;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    if new.status = 'submitted' and old.status = 'draft' then
      new.submitted_at := now();
      new.submitted_by := public.current_sicatat_user_id();
    elsif new.status = 'draft' then
      new.submitted_at := null;
      new.submitted_by := null;
    else
      new.submitted_at := old.submitted_at;
      new.submitted_by := old.submitted_by;
    end if;
    -- A submitted sheet is final; only reopening it (status -> draft) is allowed.
    if old.status = 'submitted' and new.status = 'submitted'
       and (new.readings is distinct from old.readings
            or new.notes is distinct from old.notes
            or new.tanggal is distinct from old.tanggal
            or new.shift_id is distinct from old.shift_id
            or new.team_id is distinct from old.team_id) then
      raise exception 'Lembar ini sudah dikirim. Buka kembali lembar sebelum mengubahnya.';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.daily_check_save_slot(
  p_id uuid,
  p_slot text,
  p_values jsonb
)
returns public.daily_check_sheet
language plpgsql security invoker set search_path = public as $$
declare
  saved public.daily_check_sheet;
begin
  if p_slot !~ '^[a-z0-9_]{1,24}$' then
    raise exception 'Slot pengecekan tidak valid.';
  end if;
  if jsonb_typeof(p_values) <> 'object' then
    raise exception 'Nilai pengecekan tidak valid.';
  end if;
  update public.daily_check_sheet
     set readings = case
           when p_values = '{}'::jsonb then readings - p_slot
           else jsonb_set(readings, array[p_slot], p_values, true)
         end
   where id = p_id
     and status = 'draft'
  returning * into saved;
  if saved.id is null then
    raise exception 'Lembar ini tidak dapat diubah. Lembar mungkin sudah dikirim atau tidak tersedia.';
  end if;
  return saved;
end;
$$;

