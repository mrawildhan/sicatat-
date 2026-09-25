-- Cari barang shows the newest stock per item (owner request 2026-09-25:
-- "yang pasti jika saya cari barang itu real"). Two sources report stock on
-- hand: the Ellipse Warehouse Inventory report the owner uploads, and the
-- warehouse's own "Warehouse Inventory" Google Sheet (SCALLSITE, also shown
-- by Tanya WHS) that is refreshed daily. Whichever is dated later wins; the
-- Ellipse row keeps its richer details (part no, bin, stock class).

alter table public.warehouse_stock
  add column if not exists stock_from text;

comment on column public.warehouse_stock.stock_from is
  'Where stock_on_hand came from: ellipse (Warehouse Inventory report) or sheet (warehouse Google Sheet).';

update public.warehouse_stock
set stock_from = case when stock_source = 'inventory' then 'ellipse' else 'sheet' end
where stock_from is null;

-- Called by sync-warehouse-data with the sheet's stock for items the Ellipse
-- report also lists; only rows whose current date is older are changed.
create or replace function public.warehouse_apply_sheet_stock(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  changed integer;
begin
  update public.warehouse_stock s
  set stock_on_hand = (r ->> 'stock_on_hand')::numeric,
      source_updated_on = (r ->> 'source_updated_on')::date,
      stock_from = 'sheet',
      synced_at = now()
  from jsonb_array_elements(p_rows) r
  where s.source_key = r ->> 'source_key'
    and s.stock_source = 'inventory'
    and (r ->> 'source_updated_on') is not null
    and (s.source_updated_on is null or s.source_updated_on < (r ->> 'source_updated_on')::date);
  get diagnostics changed = row_count;
  return changed;
end;
$$;

revoke all on function public.warehouse_apply_sheet_stock(jsonb) from public, anon, authenticated;
grant execute on function public.warehouse_apply_sheet_stock(jsonb) to service_role;
