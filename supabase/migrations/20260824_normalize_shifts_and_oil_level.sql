-- Keep the operational UI in English and ensure oil-level checks only appear
-- on the Feeder Breaker and the Sizer Motor. Historical readings are kept.

update public.shift
set name = case upper(code)
  when 'PAGI' then 'Day shift'
  when 'MALAM' then 'Night shift'
  else name
end
where upper(code) in ('PAGI', 'MALAM');

update public.measurement_point as point
set is_active = false
from public.equipment as equipment
where point.equipment_id = equipment.id
  and point.is_active = true
  and (
    lower(point.code) like '%oil%'
    or lower(point.label) like '%oil level%'
  )
  and not (
    lower(equipment.code) = 'feeder_breaker'
    or (
      equipment.section = 'gearbox_sizer'
      and (lower(equipment.code) = 'motor' or lower(equipment.name) = 'motor')
    )
  )
;
