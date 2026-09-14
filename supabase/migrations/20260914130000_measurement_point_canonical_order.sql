-- Canonical field order for the temperature form.
--
-- Every breaker measurement point (and the four gearbox points) had
-- sort_order = 0, so the form showed ties in arbitrary server order: Hydraulic
-- Pump 1 and 2 listed their fields differently and "Remark" could land in the
-- middle of the readings. The Flutter form already sorts by sort_order, so a
-- deterministic value per code gives every equipment the same layout:
-- temperatures first, then oil level, then the free-text remark last.

update public.measurement_point mp
set sort_order = ordering.position
from (
  values
    ('motor_de', 10),
    ('motor_nde', 20),
    ('gear_box', 30),
    ('drum_east', 40),
    ('drum_west', 50),
    ('chain_head', 60),
    ('chain_tail', 70),
    ('oil_level', 80),
    ('remark', 90)
) as ordering(code, position)
where mp.equipment_id is not null
  and mp.code = ordering.code
  and mp.sort_order is distinct from ordering.position;

-- Gearbox side points keep the order crews already see on the form.
update public.measurement_point mp
set sort_order = ordering.position
from (
  values
    ('gb_low_speed', 10),
    ('gb_intermediate', 20),
    ('gb_high_speed', 30),
    ('gb_input_shaft', 40)
) as ordering(code, position)
where mp.equipment_id is null
  and mp.code = ordering.code
  and mp.sort_order is distinct from ordering.position;
