-- =========================================================
-- 1. MASTER: MODUL & TEMPLATE
-- =========================================================

create table module (
    id              uuid primary key default gen_random_uuid(),
    code            text not null unique,        -- 'temperature_check'
    name            text not null,                -- 'Daily Temperature Check'
    description     text,
    is_active       boolean not null default true,
    created_at      timestamptz not null default now()
);

create table form_template (
    id              uuid primary key default gen_random_uuid(),
    module_id       uuid not null references module(id),
    version         text not null,                -- 'v0.4'
    schema_json     jsonb not null,                -- struktur seksi/ronde/field lengkap
    effective_from  timestamptz not null default now(),
    is_active       boolean not null default true,
    created_at      timestamptz not null default now(),
    unique (module_id, version)
);

-- =========================================================
-- 2. MASTER: EQUIPMENT & TITIK UKUR
-- =========================================================

create table equipment (
    id              uuid primary key default gen_random_uuid(),
    module_id       uuid not null references module(id),
    code            text not null,                 -- 'feeder_breaker'
    name            text not null,                 -- 'Feeder Breaker'
    section         text not null,                 -- 'gearbox_breaker' | 'gearbox_sizer'
    sort_order      int not null default 0,
    is_active       boolean not null default true,
    unique (module_id, code)
);

create table measurement_point (
    id              uuid primary key default gen_random_uuid(),
    equipment_id    uuid references equipment(id),  -- boleh null jika titik ukur berdiri sendiri (mis. gearbox breaker per sisi, bukan per equipment)
    code            text not null,                  -- 'motor_de', 'gb_low_speed', 'timing_a'
    label           text not null,                  -- 'Motor DE'
    data_type       text not null check (data_type in ('numeric','boolean','text')),
    unit            text,                           -- '°C', null untuk boolean/text
    is_required     boolean not null default true,
    sort_order      int not null default 0,
    is_active       boolean not null default true
);

create table threshold (
    id                  uuid primary key default gen_random_uuid(),
    measurement_point_id uuid not null references measurement_point(id),
    warning_min         numeric,
    warning_max         numeric,
    alarm_min           numeric,
    alarm_max           numeric,
    delta_max_per_round numeric,                    -- lonjakan maksimum wajar antar ronde (FR-43)
    effective_from      timestamptz not null default now(),
    is_active           boolean not null default true,
    source_note         text                          -- rujukan: manual OEM, engineering, dll — jangan biarkan kosong
);

-- =========================================================
-- 3. MASTER: SHIFT & USER
-- =========================================================

create table shift (
    id          uuid primary key default gen_random_uuid(),
    code        text not null unique,   -- 'PAGI' | 'MALAM'
    name        text not null,          -- 'Shift Pagi', 'Shift Malam'
    start_time  time not null,          -- 07:00
    end_time    time not null,          -- 19:00 (lintas tengah malam untuk shift Malam)
    is_active   boolean not null default true
);
-- Hanya 2 baris: shift itu sendiri tidak mengandung regu.
-- Regu mana yang bertugas di shift mana pada tanggal tertentu ditentukan tabel `roster` di bawah, bukan kode shift.

create table team (
    id          uuid primary key default gen_random_uuid(),
    code        text not null unique,   -- 'A', 'B', 'C'
    name        text not null,          -- 'Regu A'
    is_active   boolean not null default true
);
-- Dibuat SEBELUM `roster` karena roster punya foreign key ke sini — urutan create table di
-- SQL harus mengikuti urutan ketergantungan, bukan urutan cerita di dokumen ini.

create table roster (
    id          uuid primary key default gen_random_uuid(),
    tanggal     date not null,
    shift_id    uuid not null references shift(id),
    team_id     uuid not null references team(id),   -- regu yang bertugas
    is_exception boolean not null default false,        -- true jika ini pertukaran/override dari pola 3-3-3 normal
    note        text,
    unique (tanggal, shift_id)   -- satu shift pada satu tanggal, satu regu bertugas (kasus tukar dicatat lewat is_exception, bukan baris ganda)
);
-- Pola dasar: rotasi 3 hari Pagi → 3 hari Malam → 3 hari Off, bergiliran antar Regu A/B/C,
-- sehingga selalu ada satu regu standby. **[TERKONFIRMASI] Pola ini selalu konsisten, tidak
-- pernah berubah** — sehingga bisa dihitung deterministik dari satu tanggal referensi (mis.
-- "01 Jan 2026, Regu A mulai siklus Pagi") tanpa perlu input manual berulang. Cukup simpan
-- satu baris konfigurasi (`roster_anchor`: tanggal_mula, urutan_regu) dan hitung regu bertugas
-- untuk tanggal mana pun dengan (hari_selisih mod 9). Baris eksplisit di tabel `roster` tetap
-- dipertahankan sebagai *cache hasil hitungan* (bukan sumber kebenaran) — memudahkan query dan
-- tetap membuka celah kecil untuk pengecualian (tukar shift, sakit) jika suatu saat terjadi.

create table roster_anchor (
    id            uuid primary key default gen_random_uuid(),
    tanggal_mula  date not null,        -- tanggal acuan siklus dimulai
    urutan_regu   text[] not null,      -- contoh: ['A','B','C'] — urutan regu yang mengawali Pagi di tanggal_mula
    is_active     boolean not null default true
);

create table app_user (
    id          uuid primary key default gen_random_uuid(),
    nik         text unique,
    name        text not null,
    role        text not null check (role in ('crew','foreman','supervisor','admin')),
    team_id     uuid references team(id),   -- wajib untuk crew & foreman; null untuk supervisor/admin (lintas tim)
    phone       text,
    is_active   boolean not null default true,
    created_at  timestamptz not null default now()
);

-- =========================================================
-- 4. TRANSAKSI: LEMBAR, RONDE, STATUS, PEMBACAAN
-- =========================================================

create table sheet (
    id                uuid primary key default gen_random_uuid(),
    client_uuid       uuid not null unique,          -- dibuat di HP saat offline, untuk idempotency
    module_id         uuid not null references module(id),
    template_version  text not null,                  -- snapshot versi saat dibuat
    tanggal           date not null,
    shift_id          uuid not null references shift(id),
    team_id           uuid not null references team(id),   -- snapshot regu pembuat lembar saat itu; disarankan otomatis dari tabel `roster` (tanggal+shift → regu bertugas), tapi tetap disimpan eksplisit di sini agar sejarah lembar tidak berubah walau roster kemudian dikoreksi
    status            text not null default 'draft'
                        check (status in ('draft','submitted','submitted_incomplete','verified','returned')),
                        -- 'draft' tidak kedaluwarsa (FR-13a) — tetap bisa diedit lintas hari sampai lengkap
                        -- 'submitted_incomplete' = jalur override supervisor (FR-15), berbeda dari submit normal
    created_by        uuid not null references app_user(id),
    created_at        timestamptz not null default now(),
    submitted_at      timestamptz,
    verified_by        uuid references app_user(id),
    verified_at        timestamptz,
    notes             text,
    app_version        text,                          -- versi aplikasi saat submit (FR-58)
    force_submitted_by uuid references app_user(id),   -- wajib diisi jika status = submitted_incomplete
    force_submitted_at timestamptz,
    force_reason        text,                           -- wajib diisi jika status = submitted_incomplete
    unique (module_id, tanggal, shift_id, team_id),     -- audit snapshot per team
    unique (module_id, tanggal, shift_id)               -- one sheet per actual shift
);

create table sheet_contributor (
    sheet_id    uuid not null references sheet(id) on delete cascade,
    user_id     uuid not null references app_user(id),
    primary key (sheet_id, user_id)
);

create table round (
    id              uuid primary key default gen_random_uuid(),
    client_uuid     uuid not null unique,
    sheet_id        uuid not null references sheet(id) on delete cascade,
    section         text not null,                    -- 'gearbox_breaker' | 'gearbox_sizer'
    round_number    int not null,                      -- 1, 2, ...
    jam             timestamptz,                       -- waktu aktual, bukan hanya "Jam:" kosong seperti kertas
    unique (sheet_id, section, round_number)
);

create table unit_status (
    id              uuid primary key default gen_random_uuid(),
    client_uuid     uuid not null unique,
    round_id        uuid not null references round(id) on delete cascade,
    unit_code       text,                              -- 'BARAT' | 'TIMUR' | null (untuk unit tunggal spt Feeder Breaker)
    equipment_id    uuid references equipment(id),      -- null jika status ini untuk seksi sisi (bukan per-equipment)
    status          text
                        check (status is null or status in ('beroperasi','tidak_beroperasi','tidak_dapat_diakses')),
                        -- NULL = "Belum diisi" (bukan pilihan keempat, melainkan penanda belum dijawab, FR-26a)
    reason          text,                               -- wajib diisi (divalidasi di aplikasi) jika status != 'beroperasi'
    answered_at     timestamptz,                        -- null selama status masih NULL
    unique (round_id, unit_code, equipment_id)
);

create table reading (
    id                  uuid primary key default gen_random_uuid(),
    client_uuid         uuid not null unique,
    round_id            uuid not null references round(id) on delete cascade,
    unit_status_id      uuid references unit_status(id),
    measurement_point_id uuid not null references measurement_point(id),
    value_numeric        numeric,
    value_boolean         boolean,
    value_text            text,
    measured_at            timestamptz not null default now(),
    recorded_by             uuid not null references app_user(id),
    is_anomaly              boolean not null default false,   -- ditandai di klien saat submit (FR-42/43/44)
    anomaly_note             text,
    created_at               timestamptz not null default now()
);

create table attachment (
    id           uuid primary key default gen_random_uuid(),
    sheet_id     uuid references sheet(id) on delete cascade,
    reading_id   uuid references reading(id) on delete cascade,
    type         text not null default 'photo',
    url          text not null,
    uploaded_by  uuid not null references app_user(id),
    uploaded_at  timestamptz not null default now(),
    check (sheet_id is not null or reading_id is not null)
);

-- =========================================================
-- 5. AUDIT & KONTROL VERSI
-- =========================================================

create table audit_log (
    id           uuid primary key default gen_random_uuid(),
    entity_type  text not null,          -- 'sheet','reading','unit_status', dll
    entity_id    uuid not null,
    action       text not null,          -- 'create','update','submit','verify','edit_after_submit'
    old_value    jsonb,
    new_value    jsonb,
    changed_by   uuid references app_user(id),
    changed_at   timestamptz not null default now()
);

create table app_version (
    id              uuid primary key default gen_random_uuid(),
    platform        text not null default 'android',
    latest_version  text not null,
    min_version     text not null,       -- versi di bawah ini ditolak server (FR-57)
    release_notes   text,
    released_at     timestamptz not null default now()
);

-- =========================================================
-- 6. INDEX PENDUKUNG
-- =========================================================

create index idx_sheet_tanggal on sheet (tanggal, shift_id);
create index idx_sheet_draft_monitoring on sheet (status, created_at) where status = 'draft';  -- FR-60a
create index idx_reading_point_time on reading (measurement_point_id, measured_at);
create index idx_reading_round on reading (round_id);
create index idx_audit_entity on audit_log (entity_type, entity_id);

-- Verified sheets are immutable, including their rounds, unit statuses, and
-- readings. This is duplicated in the dated migration for existing projects.
create or replace function prevent_verified_sheet_mutation()
returns trigger language plpgsql as $$
begin
    if old.status = 'verified' then
        raise exception 'Verified sheets are locked and must not be edited.' using errcode = '55000';
    end if;
    return new;
end;
$$;
create trigger trg_prevent_verified_sheet_mutation
before update or delete on sheet
for each row execute function prevent_verified_sheet_mutation();

create or replace function prevent_verified_sheet_child_mutation()
returns trigger language plpgsql as $$
declare
    current_round_id uuid;
begin
    if tg_op = 'INSERT' then
        current_round_id := new.round_id;
    else
        current_round_id := old.round_id;
    end if;
    if exists (
        select 1 from round r
        join sheet s on s.id = r.sheet_id
        where r.id = current_round_id and s.status = 'verified'
    ) then
        raise exception 'Readings and unit statuses in a verified sheet are locked.' using errcode = '55000';
    end if;
    if tg_op = 'DELETE' then
        return old;
    end if;
    return new;
end;
$$;
create trigger trg_prevent_verified_status_mutation
before insert or update or delete on unit_status
for each row execute function prevent_verified_sheet_child_mutation();
create trigger trg_prevent_verified_reading_mutation
before insert or update or delete on reading
for each row execute function prevent_verified_sheet_child_mutation();
