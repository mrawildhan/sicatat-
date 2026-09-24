-- Gudang reads three Ellipse/warehouse workbooks from the owner's public
-- Drive folder "Gudang" (2026-09-24): Warehouse Inventory (AIJ17W, becomes
-- the main stock source of Cari barang), Outstanding Purchase Order (AIJOPO,
-- "Barang dipesan"), and LIST ORDER (pickup history per stock code and the
-- AMWH tool loan sheet). Edge function sync-warehouse-drive writes these
-- tables with the service role; the app only reads them.

create table if not exists public.warehouse_drive_source (
  source text primary key
    check (source in ('inventory', 'list_order', 'outstanding_po')),
  file_id text,
  file_name text,
  source_fingerprint text,
  -- Run date printed in the Ellipse report, when it has one.
  report_at timestamptz,
  row_count integer not null default 0,
  -- First check that saw the current file content.
  changed_at timestamptz,
  checked_at timestamptz,
  error text,
  error_at timestamptz
);

alter table public.warehouse_drive_source enable row level security;
drop policy if exists warehouse_drive_source_read_active on public.warehouse_drive_source;
create policy warehouse_drive_source_read_active
on public.warehouse_drive_source for select to authenticated
using (public.current_sicatat_role() is not null);

-- Stock: Warehouse Inventory rows carry more detail than the old sheet.
alter table public.warehouse_stock
  add column if not exists stock_source text not null default 'scallsite',
  add column if not exists warehouse_name text,
  add column if not exists part_no text,
  add column if not exists part_no_2 text,
  add column if not exists stock_class text,
  add column if not exists stock_type text,
  add column if not exists expense_element text,
  add column if not exists last_received_on date,
  add column if not exists last_issued_on date,
  add column if not exists inventory_value numeric,
  add column if not exists source_batch text;

alter table public.warehouse_stock
  drop constraint if exists warehouse_stock_stock_source_check;
alter table public.warehouse_stock
  add constraint warehouse_stock_stock_source_check
  check (stock_source in ('scallsite', 'inventory'));

create index if not exists idx_warehouse_stock_item_code
  on public.warehouse_stock (item_code);
create index if not exists idx_warehouse_stock_site_label
  on public.warehouse_stock (site_label);

-- A summary row of the old sheet, not an item.
delete from public.warehouse_stock where warehouse_code = 'TOTAL';

-- Pickup history from LIST ORDER (one sheet per crew or department).
create table if not exists public.warehouse_issue_history (
  id bigint generated always as identity primary key,
  item_code text not null,
  issued_on date,
  user_name text,
  quantity numeric,
  quantity_text text,
  uoi text,
  description text,
  ir_no text,
  note text,
  sheet_name text not null,
  row_no integer not null,
  source_batch text not null
);

create index if not exists idx_warehouse_issue_history_item
  on public.warehouse_issue_history (item_code, issued_on desc nulls last, row_no desc);
create index if not exists idx_warehouse_issue_history_batch
  on public.warehouse_issue_history (source_batch);

alter table public.warehouse_issue_history enable row level security;
drop policy if exists warehouse_issue_history_read_active on public.warehouse_issue_history;
create policy warehouse_issue_history_read_active
on public.warehouse_issue_history for select to authenticated
using (public.current_sicatat_role() is not null);

-- Tool loans kept in LIST ORDER's "PEMINJAMAN & OUTSTANDING TOOLS" sheet.
-- A blank end condition means the tool has not come back.
create table if not exists public.warehouse_list_order_loan (
  id bigint generated always as identity primary key,
  row_no integer not null,
  loaned_on date,
  tool_name text not null,
  quantity text,
  number_colour text,
  location text,
  borrower text,
  warehouseman text,
  condition_start text,
  condition_end text,
  returned boolean not null,
  source_batch text not null
);

create index if not exists idx_warehouse_list_order_loan_open
  on public.warehouse_list_order_loan (returned, loaned_on desc nulls last, row_no desc);
create index if not exists idx_warehouse_list_order_loan_batch
  on public.warehouse_list_order_loan (source_batch);

alter table public.warehouse_list_order_loan enable row level security;
drop policy if exists warehouse_list_order_loan_read_managers on public.warehouse_list_order_loan;
create policy warehouse_list_order_loan_read_managers
on public.warehouse_list_order_loan for select to authenticated
using (public.current_sicatat_role() in ('admin', 'supervisor_smg', 'warehouseman'));

-- Outstanding purchase order lines (ordered, not yet received).
create table if not exists public.warehouse_outstanding_po (
  id bigint generated always as identity primary key,
  po_no text not null,
  po_item_no text,
  supplier_no text,
  supplier_name text,
  item_code text,
  requestor text,
  warehouse_code text,
  description text,
  part_no text,
  qty_order numeric,
  qty_outstanding numeric,
  order_date date,
  due_date date,
  purchasing_officer text,
  source_batch text not null
);

create index if not exists idx_warehouse_outstanding_po_item
  on public.warehouse_outstanding_po (item_code);
create index if not exists idx_warehouse_outstanding_po_due
  on public.warehouse_outstanding_po (due_date);
create index if not exists idx_warehouse_outstanding_po_batch
  on public.warehouse_outstanding_po (source_batch);

alter table public.warehouse_outstanding_po enable row level security;
drop policy if exists warehouse_outstanding_po_read_active on public.warehouse_outstanding_po;
create policy warehouse_outstanding_po_read_active
on public.warehouse_outstanding_po for select to authenticated
using (public.current_sicatat_role() is not null);
