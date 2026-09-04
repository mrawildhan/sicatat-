-- Keep the selectable Site Scope master list limited to the operating sites
-- requested for SICATAT. Historical rows keep their site references because
-- inactive sites are retained rather than deleted.
insert into public.site (code, name, is_active)
values
  ('ASAMASAM', 'Asamasam', true),
  ('KINTAP', 'Kintap', true),
  ('SATUI', 'Satui', true),
  ('BATULICIN', 'Batulicin', true),
  ('NPLCT', 'NPLCT', true),
  ('SENAKIN', 'Senakin', true)
on conflict (code) do update
set name = excluded.name,
    is_active = true;

update public.site
set is_active = false
where code not in (
  'ASAMASAM',
  'KINTAP',
  'SATUI',
  'BATULICIN',
  'NPLCT',
  'SENAKIN'
);
