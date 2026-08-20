-- Skema SQLite lokal (di HP) — dijalankan sekali saat aplikasi pertama kali diinstal.
-- Struktur tabel transaksi disalin identik dari supabase/schema.sql, dengan tambahan
-- kolom sync_status. Master data (equipment, measurement_point, threshold, shift,
-- team, roster) di-cache read-only dari server, tidak dibuat manual di sini.

create table if not exists sheet (
    id                text primary key,
    client_uuid       text not null unique,
    module_id         text not null,
    template_version  text not null,
    tanggal           text not null,
    shift_id          text not null,
    team_id           text not null,
    status            text not null default 'draft',
    created_by        text not null,
    created_at        text not null,
    submitted_at      text,
    verified_by       text,
    verified_at       text,
    app_version       text,
    force_submitted_by text,
    force_submitted_at text,
    force_reason       text,
    sync_status       text not null default 'pending'
);

create table if not exists round (
    id           text primary key,
    client_uuid  text not null unique,
    sheet_id     text not null,
    section      text not null,
    round_number integer not null,
    jam          text,
    sync_status  text not null default 'pending'
);

create table if not exists unit_status (
    id           text primary key,
    client_uuid  text not null unique,
    round_id     text not null,
    unit_code    text,
    equipment_id text,
    status       text,
    reason       text,
    answered_at  text,
    sync_status  text not null default 'pending'
);

create table if not exists reading (
    id                    text primary key,
    client_uuid           text not null unique,
    round_id              text not null,
    unit_status_id        text,
    measurement_point_id  text not null,
    value_numeric         real,
    value_boolean         integer,
    value_text            text,
    measured_at           text not null,
    recorded_by           text not null,
    is_anomaly            integer not null default 0,
    anomaly_note          text,
    sync_status           text not null default 'pending'
);

create table if not exists audit_log (
    id           text primary key,
    client_uuid  text not null unique,
    entity_type  text not null,
    entity_id    text not null,
    action       text not null,
    old_value    text,
    new_value    text,
    changed_by   text,
    changed_at   text not null,
    sync_status  text not null default 'pending'
);

create table if not exists sheet_contributor (
    sheet_id  text not null,
    user_id   text not null,
    primary key (sheet_id, user_id)
);

-- Master data cache (read-only, disegarkan dari server saat online — FR-55)
create table if not exists cache_equipment (id text primary key, data text not null);
create table if not exists cache_measurement_point (id text primary key, data text not null);
create table if not exists cache_shift (id text primary key, data text not null);
create table if not exists cache_team (id text primary key, data text not null);
create table if not exists cache_roster_anchor (id text primary key, data text not null);
create table if not exists cache_app_user (id text primary key, data text not null);
create table if not exists cache_app_config (id text primary key, data text not null);

-- Antrean sinkronisasi (lihat Skema-Database-SICATAT-v0.1.md Bagian 4)
create table if not exists sync_queue (
    id            integer primary key autoincrement,
    entity_type   text not null,
    client_uuid   text not null,
    operation     text not null,
    payload_json  text not null,
    created_at    text not null default (datetime('now')),
    attempt_count integer not null default 0,
    last_error    text
);
