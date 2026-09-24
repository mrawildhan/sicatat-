-- "Terakhir diperbarui" on every spreadsheet-backed screen (Data PR, PM & CM,
-- Anggaran, Gudang) is the Drive file's own modified time, read from the
-- Last-Modified header by each sync function (owner request 2026-09-24).

create table if not exists public.data_source_status (
  source text primary key,
  -- Newest Drive "Date modified" of the files behind this source.
  modified_at timestamptz,
  checked_at timestamptz not null default now()
);

alter table public.data_source_status enable row level security;
drop policy if exists data_source_status_read_active on public.data_source_status;
create policy data_source_status_read_active
on public.data_source_status for select to authenticated
using (public.current_sicatat_role() is not null);

alter table public.warehouse_drive_source
  add column if not exists modified_at timestamptz;
