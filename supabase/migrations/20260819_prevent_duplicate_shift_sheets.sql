-- Future sheets: exactly one temperature sheet may exist for a module/date/
-- shift, regardless of which crew member's phone creates it. Existing rows are
-- intentionally preserved; this trigger only prevents new duplicates.
create or replace function public.prevent_duplicate_shift_sheet()
returns trigger
language plpgsql
as $$
begin
  if exists (
    select 1
    from public.sheet existing
    where existing.module_id = new.module_id
      and existing.tanggal = new.tanggal
      and existing.shift_id = new.shift_id
      and existing.id <> new.id
  ) then
    raise exception
      'A sheet already exists for module %, date %, and shift %.',
      new.module_id, new.tanggal, new.shift_id
      using errcode = '23505';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_duplicate_shift_sheet on public.sheet;
create trigger trg_prevent_duplicate_shift_sheet
before insert or update of module_id, tanggal, shift_id on public.sheet
for each row execute function public.prevent_duplicate_shift_sheet();
