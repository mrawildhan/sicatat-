-- Saves one check/reading of a daily check sheet without touching the others,
-- so two crew members filling different times never overwrite each other.
-- SECURITY INVOKER: the table's RLS policies still decide who may write.
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
    raise exception 'Invalid slot.';
  end if;
  if jsonb_typeof(p_values) <> 'object' then
    raise exception 'Invalid values.';
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
    raise exception 'This sheet cannot be edited. It may be submitted or unavailable.';
  end if;
  return saved;
end;
$$;

revoke all on function public.daily_check_save_slot(uuid, text, jsonb) from public, anon;
grant execute on function public.daily_check_save_slot(uuid, text, jsonb) to authenticated;
