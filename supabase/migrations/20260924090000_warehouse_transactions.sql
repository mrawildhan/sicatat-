-- Gudang pindah ke Operasional dan mendapat transaksi sendiri (2026-09-24),
-- mengikuti aplikasi Gudang buatan tim warehouse: Pengambilan Barang,
-- Peminjaman Alat, dan Penerimaan Barang + Cek PO.
--
-- * Semua pengguna aktif boleh mencari stok dan alat (keputusan pemilik).
-- * Transaksi hanya untuk admin, supervisor SMG, dan warehouseman (site-nya
--   sendiri). Tabel transaksi tidak punya policy tulis; semua penulisan lewat
--   RPC di bawah agar header + item tersimpan atomik dan tervalidasi.
-- * Google Sheet tetap sumber stok. Sinkron harian hanya meng-upsert kolom
--   yang dikirimnya, jadi kolom kondisi SICATAT di warehouse_tool aman.

create or replace function public.can_manage_warehouse_site(p_site_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case public.current_sicatat_role()
    when 'admin' then true
    when 'supervisor_smg' then true
    when 'warehouseman' then p_site_id = public.current_sicatat_site_id()
    else false
  end;
$$;

revoke all on function public.can_manage_warehouse_site(uuid) from public, anon;
grant execute on function public.can_manage_warehouse_site(uuid) to authenticated;

-- Pencarian stok dan alat untuk semua pengguna aktif.
drop policy if exists warehouse_stock_read_scoped on public.warehouse_stock;
drop policy if exists warehouse_stock_read_active on public.warehouse_stock;
create policy warehouse_stock_read_active
on public.warehouse_stock for select to authenticated
using (public.current_sicatat_role() is not null);

drop policy if exists warehouse_tool_read_scoped on public.warehouse_tool;
drop policy if exists warehouse_tool_read_active on public.warehouse_tool;
create policy warehouse_tool_read_active
on public.warehouse_tool for select to authenticated
using (public.current_sicatat_role() is not null);

-- Riwayat penerimaan dari Google Sheet (tanpa site) untuk Cek PO.
drop policy if exists warehouse_receipt_read_managers on public.warehouse_receipt;
create policy warehouse_receipt_read_managers
on public.warehouse_receipt for select to authenticated
using (public.current_sicatat_role() in ('admin', 'supervisor_smg', 'warehouseman'));

create index if not exists idx_warehouse_receipt_po
  on public.warehouse_receipt (po_number);

-- Kondisi alat yang dicatat SICATAT. Kolom tool_status tetap milik sheet.
alter table public.warehouse_tool
  add column if not exists condition_status text,
  add column if not exists condition_note text,
  add column if not exists condition_updated_at timestamptz,
  add column if not exists condition_updated_by uuid references public.app_user(id),
  add column if not exists created_by uuid references public.app_user(id);

alter table public.warehouse_tool
  drop constraint if exists warehouse_tool_condition_status_check;
alter table public.warehouse_tool
  add constraint warehouse_tool_condition_status_check
  check (condition_status is null or condition_status in (
    'ready to use', 'ready with note', 'rusak', 'hilang'
  ));

create index if not exists idx_warehouse_tool_condition_updated_by
  on public.warehouse_tool (condition_updated_by);
create index if not exists idx_warehouse_tool_created_by
  on public.warehouse_tool (created_by);

-- Pengambilan Barang ---------------------------------------------------------

create table if not exists public.warehouse_issue (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.site(id),
  issued_on date not null,
  taken_by text not null check (length(btrim(taken_by)) between 1 and 120),
  job_number text,
  note text,
  created_by uuid not null references public.app_user(id),
  created_at timestamptz not null default now()
);

create table if not exists public.warehouse_issue_item (
  id uuid primary key default gen_random_uuid(),
  issue_id uuid not null references public.warehouse_issue(id) on delete cascade,
  line_no smallint not null,
  item_code text not null,
  description text,
  uoi text,
  bin_code text,
  quantity numeric(12, 2) not null check (quantity > 0),
  unique (issue_id, line_no)
);

create index if not exists idx_warehouse_issue_site_date
  on public.warehouse_issue (site_id, issued_on desc, created_at desc);
create index if not exists idx_warehouse_issue_created_by
  on public.warehouse_issue (created_by);
create index if not exists idx_warehouse_issue_item_code
  on public.warehouse_issue_item (item_code);

-- Peminjaman Alat ------------------------------------------------------------

create table if not exists public.warehouse_tool_loan (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.site(id),
  borrower_name text not null check (length(btrim(borrower_name)) between 1 and 120),
  work_area text not null check (length(btrim(work_area)) between 1 and 120),
  loaned_on date not null,
  note text,
  created_by uuid not null references public.app_user(id),
  created_at timestamptz not null default now()
);

create table if not exists public.warehouse_tool_loan_item (
  id uuid primary key default gen_random_uuid(),
  loan_id uuid not null references public.warehouse_tool_loan(id) on delete cascade,
  tool_id uuid not null references public.warehouse_tool(id),
  registration_code text not null,
  tool_name text not null,
  quantity integer not null default 1 check (quantity > 0),
  number_colour text,
  returned_at timestamptz,
  returned_by uuid references public.app_user(id),
  return_condition text check (return_condition is null or return_condition in (
    'ready to use', 'ready with note', 'rusak', 'hilang'
  )),
  return_note text
);

-- Satu alat hanya bisa berada di satu peminjaman terbuka.
create unique index if not exists warehouse_tool_loan_item_one_open
  on public.warehouse_tool_loan_item (tool_id)
  where returned_at is null;
create index if not exists idx_warehouse_tool_loan_site_date
  on public.warehouse_tool_loan (site_id, loaned_on desc);
create index if not exists idx_warehouse_tool_loan_created_by
  on public.warehouse_tool_loan (created_by);
create index if not exists idx_warehouse_tool_loan_item_loan
  on public.warehouse_tool_loan_item (loan_id);
create index if not exists idx_warehouse_tool_loan_item_returned_by
  on public.warehouse_tool_loan_item (returned_by);

-- Penerimaan Barang ----------------------------------------------------------

create table if not exists public.warehouse_goods_receipt (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.site(id),
  received_on date not null,
  po_number text not null check (length(btrim(po_number)) between 1 and 60),
  delivery_note text not null check (length(btrim(delivery_note)) between 1 and 80),
  supplier text,
  note text,
  created_by uuid not null references public.app_user(id),
  created_at timestamptz not null default now()
);

create table if not exists public.warehouse_goods_receipt_item (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.warehouse_goods_receipt(id) on delete cascade,
  line_no smallint not null,
  item_no text,
  stock_code text,
  description text not null,
  requestor text,
  quantity numeric(12, 2) not null check (quantity > 0),
  uoi text,
  unique (receipt_id, line_no)
);

create index if not exists idx_warehouse_goods_receipt_site_date
  on public.warehouse_goods_receipt (site_id, received_on desc, created_at desc);
create index if not exists idx_warehouse_goods_receipt_po
  on public.warehouse_goods_receipt (po_number);
create index if not exists idx_warehouse_goods_receipt_created_by
  on public.warehouse_goods_receipt (created_by);
create index if not exists idx_warehouse_goods_receipt_item_stock
  on public.warehouse_goods_receipt_item (stock_code);

-- RLS: baca untuk pengelola site, tulis hanya lewat RPC. ---------------------

alter table public.warehouse_issue enable row level security;
alter table public.warehouse_issue_item enable row level security;
alter table public.warehouse_tool_loan enable row level security;
alter table public.warehouse_tool_loan_item enable row level security;
alter table public.warehouse_goods_receipt enable row level security;
alter table public.warehouse_goods_receipt_item enable row level security;

drop policy if exists warehouse_issue_read on public.warehouse_issue;
create policy warehouse_issue_read on public.warehouse_issue
for select to authenticated using (public.can_manage_warehouse_site(site_id));

drop policy if exists warehouse_issue_item_read on public.warehouse_issue_item;
create policy warehouse_issue_item_read on public.warehouse_issue_item
for select to authenticated using (exists (
  select 1 from public.warehouse_issue i
  where i.id = issue_id and public.can_manage_warehouse_site(i.site_id)
));

drop policy if exists warehouse_tool_loan_read on public.warehouse_tool_loan;
create policy warehouse_tool_loan_read on public.warehouse_tool_loan
for select to authenticated using (public.can_manage_warehouse_site(site_id));

-- Pengguna lain cukup tahu alat mana yang sedang dipinjam; itu lewat
-- warehouse_tools_on_loan() tanpa nama peminjam.
drop policy if exists warehouse_tool_loan_item_read on public.warehouse_tool_loan_item;
create policy warehouse_tool_loan_item_read on public.warehouse_tool_loan_item
for select to authenticated using (exists (
  select 1 from public.warehouse_tool_loan l
  where l.id = loan_id and public.can_manage_warehouse_site(l.site_id)
));

drop policy if exists warehouse_goods_receipt_read on public.warehouse_goods_receipt;
create policy warehouse_goods_receipt_read on public.warehouse_goods_receipt
for select to authenticated using (public.can_manage_warehouse_site(site_id));

drop policy if exists warehouse_goods_receipt_item_read on public.warehouse_goods_receipt_item;
create policy warehouse_goods_receipt_item_read on public.warehouse_goods_receipt_item
for select to authenticated using (exists (
  select 1 from public.warehouse_goods_receipt r
  where r.id = receipt_id and public.can_manage_warehouse_site(r.site_id)
));

-- Helpers --------------------------------------------------------------------

create or replace function public.warehouse_require_manager(p_site_id uuid)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare
  v_user uuid := public.current_sicatat_user_id();
begin
  if v_user is null or p_site_id is null or not public.can_manage_warehouse_site(p_site_id) then
    raise exception 'Anda tidak berhak mencatat transaksi Gudang untuk site ini.'
      using errcode = '42501';
  end if;
  return v_user;
end;
$$;

revoke all on function public.warehouse_require_manager(uuid) from public, anon, authenticated;

create or replace function public.warehouse_text(p_value text, p_max integer)
returns text language sql immutable set search_path = public as $$
  select nullif(left(btrim(coalesce(p_value, '')), p_max), '');
$$;

create or replace function public.warehouse_quantity(p_value jsonb, p_line integer)
returns numeric language plpgsql immutable set search_path = public as $$
declare
  v numeric;
begin
  begin
    v := (p_value #>> '{}')::numeric;
  exception when others then
    v := null;
  end;
  if v is null or v <= 0 then
    raise exception 'Jumlah pada baris % harus lebih dari 0.', p_line using errcode = '22023';
  end if;
  return v;
end;
$$;

-- Pengambilan Barang ---------------------------------------------------------

create or replace function public.warehouse_issue_create(
  p_site_id uuid,
  p_issued_on date,
  p_taken_by text,
  p_job_number text,
  p_note text,
  p_items jsonb
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := public.warehouse_require_manager(p_site_id);
  v_id uuid;
  v_item jsonb;
  v_line integer := 0;
begin
  if public.warehouse_text(p_taken_by, 120) is null then
    raise exception 'Nama pengambil wajib diisi.' using errcode = '22023';
  end if;
  if p_issued_on is null or p_issued_on > current_date + 1 then
    raise exception 'Tanggal pengambilan tidak valid.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'Isi minimal satu item.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 30 then
    raise exception 'Maksimal 30 item per pengambilan.' using errcode = '22023';
  end if;

  insert into public.warehouse_issue (site_id, issued_on, taken_by, job_number, note, created_by)
  values (
    p_site_id,
    p_issued_on,
    public.warehouse_text(p_taken_by, 120),
    public.warehouse_text(p_job_number, 60),
    public.warehouse_text(p_note, 500),
    v_user
  )
  returning id into v_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_line := v_line + 1;
    if public.warehouse_text(v_item ->> 'item_code', 40) is null then
      raise exception 'Kode SC pada baris % wajib diisi.', v_line using errcode = '22023';
    end if;
    insert into public.warehouse_issue_item (
      issue_id, line_no, item_code, description, uoi, bin_code, quantity
    ) values (
      v_id,
      v_line,
      upper(public.warehouse_text(v_item ->> 'item_code', 40)),
      public.warehouse_text(v_item ->> 'description', 300),
      public.warehouse_text(v_item ->> 'uoi', 20),
      public.warehouse_text(v_item ->> 'bin_code', 40),
      public.warehouse_quantity(v_item -> 'quantity', v_line)
    );
  end loop;
  return v_id;
end;
$$;

-- Alat: registrasi, ubah kondisi, pinjam, kembali -----------------------------

create or replace function public.warehouse_tool_register(
  p_site_id uuid,
  p_registration_code text,
  p_tool_name text,
  p_mnemonic text,
  p_serial_number text,
  p_status text,
  p_note text
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := public.warehouse_require_manager(p_site_id);
  v_code text := upper(public.warehouse_text(p_registration_code, 60));
  v_name text := public.warehouse_text(p_tool_name, 160);
  v_site_label text;
  v_id uuid;
begin
  if v_code is null or v_name is null then
    raise exception 'Kode registrasi dan nama alat wajib diisi.' using errcode = '22023';
  end if;
  if coalesce(p_status, '') not in ('ready to use', 'ready with note', 'rusak', 'hilang') then
    raise exception 'Status alat tidak valid.' using errcode = '22023';
  end if;
  select name into v_site_label from public.site where id = p_site_id;
  if exists (
    select 1 from public.warehouse_tool
    where site_id = p_site_id and upper(registration_code) = v_code
  ) then
    raise exception 'Kode registrasi % sudah terdaftar di %.', v_code, v_site_label
      using errcode = '23505';
  end if;
  insert into public.warehouse_tool (
    source_key, registration_code, tool_name, mnemonic, serial_number,
    tool_status, note, site_label, site_id,
    condition_status, condition_note, condition_updated_at, condition_updated_by, created_by
  ) values (
    'sicatat-tool|' || p_site_id || '|' || v_code,
    v_code,
    v_name,
    public.warehouse_text(p_mnemonic, 60),
    public.warehouse_text(p_serial_number, 80),
    p_status,
    public.warehouse_text(p_note, 500),
    v_site_label,
    p_site_id,
    p_status,
    public.warehouse_text(p_note, 500),
    now(),
    v_user,
    v_user
  )
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.warehouse_tool_set_condition(
  p_tool_id uuid,
  p_status text,
  p_note text
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_site uuid;
  v_user uuid;
begin
  select site_id into v_site from public.warehouse_tool where id = p_tool_id;
  v_user := public.warehouse_require_manager(v_site);
  if coalesce(p_status, '') not in ('ready to use', 'ready with note', 'rusak', 'hilang') then
    raise exception 'Status alat tidak valid.' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.warehouse_tool_loan_item
    where tool_id = p_tool_id and returned_at is null
  ) then
    raise exception 'Alat masih dipinjam. Proses pengembaliannya terlebih dahulu.'
      using errcode = '22023';
  end if;
  update public.warehouse_tool
     set condition_status = p_status,
         condition_note = public.warehouse_text(p_note, 500),
         condition_updated_at = now(),
         condition_updated_by = v_user
   where id = p_tool_id;
end;
$$;

create or replace function public.warehouse_tool_loan_create(
  p_site_id uuid,
  p_borrower_name text,
  p_work_area text,
  p_loaned_on date,
  p_note text,
  p_items jsonb
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := public.warehouse_require_manager(p_site_id);
  v_id uuid;
  v_item jsonb;
  v_line integer := 0;
  v_tool public.warehouse_tool;
  v_status text;
  v_quantity integer;
begin
  if public.warehouse_text(p_borrower_name, 120) is null then
    raise exception 'Nama peminjam wajib diisi.' using errcode = '22023';
  end if;
  if public.warehouse_text(p_work_area, 120) is null then
    raise exception 'Area kerja wajib diisi.' using errcode = '22023';
  end if;
  if p_loaned_on is null or p_loaned_on > current_date + 1 then
    raise exception 'Tanggal pinjam tidak valid.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'Pilih minimal satu alat.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 20 then
    raise exception 'Maksimal 20 alat per peminjaman.' using errcode = '22023';
  end if;

  insert into public.warehouse_tool_loan (site_id, borrower_name, work_area, loaned_on, note, created_by)
  values (
    p_site_id,
    public.warehouse_text(p_borrower_name, 120),
    public.warehouse_text(p_work_area, 120),
    p_loaned_on,
    public.warehouse_text(p_note, 500),
    v_user
  )
  returning id into v_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_line := v_line + 1;
    select * into v_tool from public.warehouse_tool
     where id = (v_item ->> 'tool_id')::uuid
     for update;
    if v_tool.id is null or v_tool.site_id is distinct from p_site_id then
      raise exception 'Alat pada baris % tidak ditemukan di site ini.', v_line using errcode = '22023';
    end if;
    v_status := lower(coalesce(v_tool.condition_status, v_tool.tool_status, ''));
    if v_status in ('rusak', 'hilang') then
      raise exception 'Alat % berstatus %, tidak dapat dipinjam.', v_tool.tool_name, v_status
        using errcode = '22023';
    end if;
    v_quantity := round(public.warehouse_quantity(v_item -> 'quantity', v_line));
    begin
      insert into public.warehouse_tool_loan_item (
        loan_id, tool_id, registration_code, tool_name, quantity, number_colour
      ) values (
        v_id,
        v_tool.id,
        v_tool.registration_code,
        v_tool.tool_name,
        greatest(v_quantity, 1),
        public.warehouse_text(v_item ->> 'number_colour', 80)
      );
    exception when unique_violation then
      raise exception 'Alat % (%) masih dipinjam atau dipilih dua kali.', v_tool.tool_name, v_tool.registration_code
        using errcode = '23505';
    end;
  end loop;
  return v_id;
end;
$$;

create or replace function public.warehouse_tool_return(
  p_item_id uuid,
  p_condition text,
  p_note text
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_item public.warehouse_tool_loan_item;
  v_site uuid;
  v_user uuid;
begin
  select * into v_item from public.warehouse_tool_loan_item where id = p_item_id for update;
  select site_id into v_site from public.warehouse_tool_loan where id = v_item.loan_id;
  v_user := public.warehouse_require_manager(v_site);
  if v_item.returned_at is not null then
    raise exception 'Alat ini sudah dikembalikan.' using errcode = '22023';
  end if;
  if coalesce(p_condition, '') not in ('ready to use', 'ready with note', 'rusak', 'hilang') then
    raise exception 'Kondisi pengembalian tidak valid.' using errcode = '22023';
  end if;
  if public.warehouse_text(p_note, 500) is null then
    raise exception 'Catatan pengembalian wajib diisi.' using errcode = '22023';
  end if;
  update public.warehouse_tool_loan_item
     set returned_at = now(),
         returned_by = v_user,
         return_condition = p_condition,
         return_note = public.warehouse_text(p_note, 500)
   where id = p_item_id;
  update public.warehouse_tool
     set condition_status = p_condition,
         condition_note = public.warehouse_text(p_note, 500),
         condition_updated_at = now(),
         condition_updated_by = v_user
   where id = v_item.tool_id;
end;
$$;

-- Status alat yang sedang dipinjam untuk semua pengguna (tanpa data peminjam).
create or replace function public.warehouse_tools_on_loan()
returns table (tool_id uuid, loaned_on date)
language sql stable security definer set search_path = public as $$
  select i.tool_id, l.loaned_on
  from public.warehouse_tool_loan_item i
  join public.warehouse_tool_loan l on l.id = i.loan_id
  where i.returned_at is null
    and public.current_sicatat_role() is not null;
$$;

-- Penerimaan Barang ----------------------------------------------------------

create or replace function public.warehouse_goods_receipt_create(
  p_site_id uuid,
  p_received_on date,
  p_po_number text,
  p_delivery_note text,
  p_supplier text,
  p_note text,
  p_items jsonb
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := public.warehouse_require_manager(p_site_id);
  v_id uuid;
  v_item jsonb;
  v_line integer := 0;
begin
  if public.warehouse_text(p_po_number, 60) is null then
    raise exception 'Nomor PO wajib diisi.' using errcode = '22023';
  end if;
  if public.warehouse_text(p_delivery_note, 80) is null then
    raise exception 'Nomor DO / surat jalan wajib diisi.' using errcode = '22023';
  end if;
  if p_received_on is null or p_received_on > current_date + 1 then
    raise exception 'Tanggal penerimaan tidak valid.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'Isi minimal satu item yang diterima.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 50 then
    raise exception 'Maksimal 50 item per penerimaan.' using errcode = '22023';
  end if;

  insert into public.warehouse_goods_receipt (
    site_id, received_on, po_number, delivery_note, supplier, note, created_by
  ) values (
    p_site_id,
    p_received_on,
    upper(public.warehouse_text(p_po_number, 60)),
    public.warehouse_text(p_delivery_note, 80),
    public.warehouse_text(p_supplier, 160),
    public.warehouse_text(p_note, 500),
    v_user
  )
  returning id into v_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_line := v_line + 1;
    if public.warehouse_text(v_item ->> 'description', 300) is null then
      raise exception 'Deskripsi pada baris % wajib diisi.', v_line using errcode = '22023';
    end if;
    insert into public.warehouse_goods_receipt_item (
      receipt_id, line_no, item_no, stock_code, description, requestor, quantity, uoi
    ) values (
      v_id,
      v_line,
      public.warehouse_text(v_item ->> 'item_no', 20),
      upper(public.warehouse_text(v_item ->> 'stock_code', 40)),
      public.warehouse_text(v_item ->> 'description', 300),
      public.warehouse_text(v_item ->> 'requestor', 120),
      public.warehouse_quantity(v_item -> 'quantity', v_line),
      public.warehouse_text(v_item ->> 'uoi', 20)
    );
  end loop;
  return v_id;
end;
$$;

revoke all on function public.warehouse_issue_create(uuid, date, text, text, text, jsonb) from public, anon;
revoke all on function public.warehouse_tool_register(uuid, text, text, text, text, text, text) from public, anon;
revoke all on function public.warehouse_tool_set_condition(uuid, text, text) from public, anon;
revoke all on function public.warehouse_tool_loan_create(uuid, text, text, date, text, jsonb) from public, anon;
revoke all on function public.warehouse_tool_return(uuid, text, text) from public, anon;
revoke all on function public.warehouse_tools_on_loan() from public, anon;
revoke all on function public.warehouse_goods_receipt_create(uuid, date, text, text, text, text, jsonb) from public, anon;

grant execute on function public.warehouse_issue_create(uuid, date, text, text, text, jsonb) to authenticated;
grant execute on function public.warehouse_tool_register(uuid, text, text, text, text, text, text) to authenticated;
grant execute on function public.warehouse_tool_set_condition(uuid, text, text) to authenticated;
grant execute on function public.warehouse_tool_loan_create(uuid, text, text, date, text, jsonb) to authenticated;
grant execute on function public.warehouse_tool_return(uuid, text, text) to authenticated;
grant execute on function public.warehouse_tools_on_loan() to authenticated;
grant execute on function public.warehouse_goods_receipt_create(uuid, date, text, text, text, text, jsonb) to authenticated;
