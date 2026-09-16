-- Pusat Dokumen kept its Google Drive listing only in the edge function's
-- memory, so the first question after ten idle minutes paid for a full public
-- folder crawl (about six seconds). The listing now lives here: the function
-- reads it, and refreshes it in the background once a day.
--
-- Only file names, Drive ids, and folder paths are stored — never file
-- contents. The documents themselves stay in Google Drive.

create table if not exists public.technical_document_index (
  drive_id text primary key,
  name text not null,
  folder_path text not null,
  synced_at timestamptz not null default now()
);

create index if not exists idx_technical_document_index_synced_at
  on public.technical_document_index (synced_at desc);

-- Deliberately no policies: the listing is written and read only by the
-- ask-technical-documents edge function with the service role, which bypasses
-- RLS. Denying every other role keeps the anon key from reading it.
alter table public.technical_document_index enable row level security;

revoke all on public.technical_document_index from anon, authenticated;
