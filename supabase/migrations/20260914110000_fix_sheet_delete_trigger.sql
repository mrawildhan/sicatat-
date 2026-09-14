-- prevent_verified_sheet_mutation fires BEFORE UPDATE OR DELETE but always
-- returned NEW. NEW is NULL for DELETE, so Postgres silently skipped every
-- sheet delete since 20260820: the app's Delete sheet removed the local copy,
-- got no error, and the sheet reappeared on the next sync while still holding
-- its module+date+shift slot. Verified sheets stay locked.
create or replace function public.prevent_verified_sheet_mutation()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'verified' then
    raise exception 'Verified sheets are locked and must not be edited.'
      using errcode = '55000';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
