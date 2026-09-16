-- Permintaan Barang gained a third work area (COP) and an optional product
-- link, so the planner can open exactly the item the crew meant instead of
-- guessing from the name.

alter table public.material_request
  drop constraint if exists material_request_request_area_check;

alter table public.material_request
  add constraint material_request_request_area_check
  check (request_area = any (array['lv'::text, 'cop'::text, 'drilling'::text]));

alter table public.material_request
  add column if not exists product_url text;

-- Empty strings would defeat "is null" checks in the app; keep the column
-- either absent or a real http(s) address.
alter table public.material_request
  drop constraint if exists material_request_product_url_check;

alter table public.material_request
  add constraint material_request_product_url_check
  check (
    product_url is null
    or product_url ~ '^https?://[^[:space:]]+$'
  );
