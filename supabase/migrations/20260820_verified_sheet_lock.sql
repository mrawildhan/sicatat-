-- SICATAT v2.1: verified inspection records are immutable at the database
-- boundary. The mobile app also blocks edits, but this protects against stale
-- clients and direct PostgREST calls.

create or replace function public.prevent_verified_sheet_mutation()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'verified' then
    raise exception 'Verified sheets are locked and must not be edited.'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_verified_sheet_mutation on public.sheet;
create trigger trg_prevent_verified_sheet_mutation
before update or delete on public.sheet
for each row execute function public.prevent_verified_sheet_mutation();

create or replace function public.prevent_verified_sheet_child_mutation()
returns trigger
language plpgsql
as $$
declare
  current_round_id uuid;
begin
  if tg_op = 'INSERT' then
    current_round_id := new.round_id;
  else
    current_round_id := old.round_id;
  end if;
  if exists (
    select 1
    from public.round r
    join public.sheet s on s.id = r.sheet_id
    where r.id = current_round_id and s.status = 'verified'
  ) then
    raise exception 'Readings and unit statuses in a verified sheet are locked.'
      using errcode = '55000';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_verified_status_mutation on public.unit_status;
create trigger trg_prevent_verified_status_mutation
before insert or update or delete on public.unit_status
for each row execute function public.prevent_verified_sheet_child_mutation();

drop trigger if exists trg_prevent_verified_reading_mutation on public.reading;
create trigger trg_prevent_verified_reading_mutation
before insert or update or delete on public.reading
for each row execute function public.prevent_verified_sheet_child_mutation();
