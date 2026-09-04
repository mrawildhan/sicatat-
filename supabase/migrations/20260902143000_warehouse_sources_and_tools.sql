-- Warehouse v2 keeps the Google Sheet snapshot safe when an operator is
-- editing it, and adds the approved Kintap stock and tool-register sources.

alter table public.warehouse_sync_log
  add column if not exists tool_rows integer not null default 0,
  add column if not exists source_summary jsonb not null default '{}'::jsonb;

create table if not exists public.warehouse_tool (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  registration_code text not null,
  tool_name text not null,
  mnemonic text,
  serial_number text,
  tool_status text,
  note text,
  last_log_on date,
  site_label text not null,
  site_id uuid references public.site(id),
  synced_at timestamptz not null default now()
);

create index if not exists idx_warehouse_tool_search
  on public.warehouse_tool (site_id, registration_code);

alter table public.warehouse_tool enable row level security;

drop policy if exists warehouse_tool_read_scoped on public.warehouse_tool;
create policy warehouse_tool_read_scoped
on public.warehouse_tool for select to authenticated
using (public.can_read_warehouse_site(site_id));
