// pull-sync.js — tarik draft milik SATU regu dari Supabase ke SQLite lokal.
//
// KENAPA INI ADA: sync-engine.js cuma satu arah (HP -> Supabase). Kalau crew
// pakai HP masing-masing (bukan satu HP gantian), lembar draft yang dibuat &
// sebagian diisi di HP orang lain (regu sama) tidak akan pernah muncul di HP
// ini -- kalau device ini lalu bikin lembar baru untuk tanggal/shift/regu
// yang sama, insert-nya akan ditolak server (unique constraint) dan ditandai
// 'conflict' oleh sync-engine.js, MEMBUANG DIAM-DIAM seluruh isian device ini
// (lihat catatan panjang di sync-engine.js baris ~110-123).
//
// Solusinya BUKAN sync dua-arah penuh (kompleks, berisiko) -- cukup: sebelum
// user melihat/bikin lembar, tarik draft regunya sendiri dari server kalau
// belum ada di lokal. Setelah itu createSheet() di db.js (yang sudah cek
// "sheet dengan module+tanggal+shift+team ini sudah ada?") otomatis
// menyambung ke lembar yang sama, bukan bikin duplikat.
//
// PRINSIP: insert-if-missing SAJA, tidak pernah overwrite baris lokal yang
// sudah ada -- baris lokal dianggap sumber kebenaran untuk device ini,
// supaya tidak bentrok dengan perubahan lokal yang belum sempat di-push.

import { supabase } from './supabase-client.js';
import { initDb } from './db.js';

async function existingIds(database, table, ids) {
  if (ids.length === 0) return new Set();
  const placeholders = ids.map(() => '?').join(',');
  const res = await database.query(`select id from ${table} where id in (${placeholders})`, ids);
  return new Set((res.values ?? []).map((r) => r.id));
}

function boolToInt(v) {
  return v === null || v === undefined ? null : (v ? 1 : 0);
}

export async function pullTeamDrafts(teamId) {
  if (!navigator.onLine || !teamId) return;

  const database = await initDb();

  // ---- SHEET ----
  const { data: serverSheets, error: sheetErr } = await supabase
    .from('sheet')
    .select('id, client_uuid, module_id, template_version, tanggal, shift_id, team_id, status, created_by, created_at, submitted_at, app_version, force_submitted_by, force_submitted_at, force_reason')
    .eq('team_id', teamId)
    .eq('status', 'draft');
  if (sheetErr) throw new Error(`Gagal tarik lembar regu: ${sheetErr.message}`);
  if ((serverSheets ?? []).length === 0) return; // tidak ada draft di server utk regu ini -- selesai

  const haveSheetIds = await existingIds(database, 'sheet', serverSheets.map((s) => s.id));
  for (const s of serverSheets) {
    if (haveSheetIds.has(s.id)) continue;
    await database.run(
      `insert into sheet (id, client_uuid, module_id, template_version, tanggal, shift_id, team_id,
        status, created_by, created_at, submitted_at, app_version, force_submitted_by, force_submitted_at,
        force_reason, sync_status) values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [s.id, s.client_uuid, s.module_id, s.template_version, s.tanggal, s.shift_id, s.team_id,
       s.status, s.created_by, s.created_at, s.submitted_at, s.app_version, s.force_submitted_by,
       s.force_submitted_at, s.force_reason, 'synced']
    );
  }

  // Semua sheet_id draft milik regu ini yang SEKARANG ada lokal (lama + baru
  // ditarik) -- dasar buat menarik round/unit_status/reading/contributor.
  const sheetIds = serverSheets.map((s) => s.id);

  // ---- ROUND ----
  const { data: serverRounds, error: roundErr } = await supabase
    .from('round')
    .select('id, client_uuid, sheet_id, section, round_number, jam')
    .in('sheet_id', sheetIds);
  if (roundErr) throw new Error(`Gagal tarik ronde: ${roundErr.message}`);

  const haveRoundIds = await existingIds(database, 'round', (serverRounds ?? []).map((r) => r.id));
  for (const r of serverRounds ?? []) {
    if (haveRoundIds.has(r.id)) continue;
    await database.run(
      `insert into round (id, client_uuid, sheet_id, section, round_number, jam, sync_status)
       values (?,?,?,?,?,?,?)`,
      [r.id, r.client_uuid, r.sheet_id, r.section, r.round_number, r.jam, 'synced']
    );
  }

  const roundIds = (serverRounds ?? []).map((r) => r.id);
  if (roundIds.length === 0) return;

  // ---- UNIT_STATUS ----
  const { data: serverUnitStatuses, error: usErr } = await supabase
    .from('unit_status')
    .select('id, client_uuid, round_id, unit_code, equipment_id, status, reason, answered_at')
    .in('round_id', roundIds);
  if (usErr) throw new Error(`Gagal tarik status unit: ${usErr.message}`);

  const haveUsIds = await existingIds(database, 'unit_status', (serverUnitStatuses ?? []).map((u) => u.id));
  for (const u of serverUnitStatuses ?? []) {
    if (haveUsIds.has(u.id)) continue;
    await database.run(
      `insert into unit_status (id, client_uuid, round_id, unit_code, equipment_id, status, reason, answered_at, sync_status)
       values (?,?,?,?,?,?,?,?,?)`,
      [u.id, u.client_uuid, u.round_id, u.unit_code, u.equipment_id, u.status, u.reason, u.answered_at, 'synced']
    );
  }

  // ---- READING ----
  const { data: serverReadings, error: rdErr } = await supabase
    .from('reading')
    .select('id, client_uuid, round_id, unit_status_id, measurement_point_id, value_numeric, value_boolean, value_text, measured_at, recorded_by, is_anomaly')
    .in('round_id', roundIds);
  if (rdErr) throw new Error(`Gagal tarik pembacaan: ${rdErr.message}`);

  const haveReadingIds = await existingIds(database, 'reading', (serverReadings ?? []).map((rd) => rd.id));
  for (const rd of serverReadings ?? []) {
    if (haveReadingIds.has(rd.id)) continue;
    await database.run(
      `insert into reading (id, client_uuid, round_id, unit_status_id, measurement_point_id,
        value_numeric, value_boolean, value_text, measured_at, recorded_by, is_anomaly, sync_status)
       values (?,?,?,?,?,?,?,?,?,?,?,?)`,
      [rd.id, rd.client_uuid, rd.round_id, rd.unit_status_id, rd.measurement_point_id,
       rd.value_numeric, boolToInt(rd.value_boolean), rd.value_text, rd.measured_at, rd.recorded_by,
       boolToInt(rd.is_anomaly) ?? 0, 'synced']
    );
  }

  // ---- SHEET_CONTRIBUTOR (primary key gabungan, bukan by id) ----
  const { data: serverContributors, error: scErr } = await supabase
    .from('sheet_contributor')
    .select('sheet_id, user_id')
    .in('sheet_id', sheetIds);
  if (scErr) throw new Error(`Gagal tarik kontributor: ${scErr.message}`);

  for (const c of serverContributors ?? []) {
    const existing = await database.query(
      'select 1 from sheet_contributor where sheet_id = ? and user_id = ?',
      [c.sheet_id, c.user_id]
    );
    if (existing.values?.length) continue;
    await database.run(
      'insert into sheet_contributor (sheet_id, user_id) values (?, ?)',
      [c.sheet_id, c.user_id]
    );
  }
}
