// db.js — lapisan data lokal.
//
// Ini pembungkus di atas @capacitor-community/sqlite. Semua layar (screens/*.js)
// bicara ke modul ini, TIDAK PERNAH langsung ke SQLite atau Supabase. Ini yang
// membuat sync-engine.js (belum ditulis) bisa dites terpisah dari UI.
//
// Prinsip dari rancangan (Skema-Database-SICATAT-v0.1.md Bagian 1 & 4):
//   1. Setiap tulis lokal juga menulis baris ke sync_queue dengan client_uuid.
//   2. client_uuid dibuat DI SINI (bukan menunggu server), supaya app tetap
//      berfungsi 100% offline dan retry sinkron tidak pernah membuat duplikat.
//   3. Modul ini tidak tahu apa-apa soal Supabase — itu tugas sync-engine.js.

import { CapacitorSQLite, SQLiteConnection } from '@capacitor-community/sqlite';

const sqlite = new SQLiteConnection(CapacitorSQLite);
const DB_NAME = 'sicatat_local';

// SEMENTARA: Gearbox Breaker + Sizer, Ronde 1 & 2 tetap. Idealnya dibaca dari
// struktur form_template, bukan di-hardcode seperti sekarang. Satu tempat
// (bukan didefinisikan ulang di summary.js/sheetList.js/incompleteList.js)
// supaya definisi "8 sisi yang diharapkan" tidak pernah berbeda-beda.
// unitCode TETAP 'BARAT'/'TIMUR' (nilai data mentah, dibandingkan langsung ke
// unit_status.unit_code di server/lokal) -- cuma `label` (yang benar-benar
// tampil ke user) yang diterjemahkan West/East.
export const EXPECTED_SIDES = [
  { section: 'gearbox_breaker', roundNumber: 1, unitCode: 'BARAT', label: 'Gb. Breaker — Round 1 · West' },
  { section: 'gearbox_breaker', roundNumber: 1, unitCode: 'TIMUR', label: 'Gb. Breaker — Round 1 · East' },
  { section: 'gearbox_sizer', roundNumber: 1, unitCode: 'BARAT', label: 'Gb. Sizer — Round 1 · West' },
  { section: 'gearbox_sizer', roundNumber: 1, unitCode: 'TIMUR', label: 'Gb. Sizer — Round 1 · East' },
  { section: 'gearbox_breaker', roundNumber: 2, unitCode: 'BARAT', label: 'Gb. Breaker — Round 2 · West' },
  { section: 'gearbox_breaker', roundNumber: 2, unitCode: 'TIMUR', label: 'Gb. Breaker — Round 2 · East' },
  { section: 'gearbox_sizer', roundNumber: 2, unitCode: 'BARAT', label: 'Gb. Sizer — Round 2 · West' },
  { section: 'gearbox_sizer', roundNumber: 2, unitCode: 'TIMUR', label: 'Gb. Sizer — Round 2 · East' },
];

let db = null;

export function uuid() {
  // UUID v4 sederhana — cukup untuk client_uuid, tidak perlu kriptografis kuat.
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

export async function initDb() {
  if (db) return db;
  db = await sqlite.createConnection(DB_NAME, false, 'no-encryption', 1, false);
  await db.open();

  const schemaRes = await fetch('js/lib/local-schema.sql');
  const schemaSql = await schemaRes.text();

  // PENTING: pisah per statement dengan tanda ';', TAPI buang baris komentar
  // (--...) dari DALAM tiap potongan, bukan menolak seluruh potongan hanya
  // karena kebetulan diawali baris komentar. Bug versi sebelumnya: kalau ada
  // komentar penjelasan tepat di atas satu `create table`, seluruh statement
  // itu ikut terbuang tanpa error apa pun — tabelnya diam-diam tidak pernah
  // dibuat, baru ketahuan belakangan saat di-query ("no such table").
  const statements = schemaSql
    .split(';')
    .map((chunk) =>
      chunk
        .split('\n')
        .filter((line) => !line.trim().startsWith('--'))
        .join('\n')
        .trim()
    )
    .filter((s) => s.length > 0);

  for (const stmt of statements) {
    await db.execute(stmt + ';');
  }
  return db;
}

// ---- Helper generik: tulis + antre sinkron dalam satu langkah ----
async function insertWithQueue(table, columns, values, entityType) {
  const database = await initDb();
  const placeholders = columns.map(() => '?').join(',');
  await database.run(
    `insert into ${table} (${columns.join(',')}) values (${placeholders})`,
    values
  );
  const clientUuidIndex = columns.indexOf('client_uuid');
  const clientUuid = values[clientUuidIndex];
  const payload = Object.fromEntries(columns.map((c, i) => [c, values[i]]));
  await database.run(
    `insert into sync_queue (entity_type, client_uuid, operation, payload_json) values (?,?,?,?)`,
    [entityType, clientUuid, 'insert', JSON.stringify(payload)]
  );
}

// ---- SHEET ----
export async function createSheet({ moduleId, templateVersion, tanggal, shiftId, teamId, createdBy }) {
  const database = await initDb();

  const existing = await database.query(
    'select id from sheet where module_id = ? and tanggal = ? and shift_id = ? and team_id = ?',
    [moduleId, tanggal, shiftId, teamId]
  );
  if (existing.values?.length) {
    return existing.values[0].id;
  }

  const id = uuid();
  const clientUuid = uuid();
  await insertWithQueue(
    'sheet',
    ['id', 'client_uuid', 'module_id', 'template_version', 'tanggal', 'shift_id', 'team_id',
     'status', 'created_by', 'created_at', 'sync_status'],
    [id, clientUuid, moduleId, templateVersion, tanggal, shiftId, teamId,
     'draft', createdBy, new Date().toISOString(), 'pending'],
    'sheet'
  );
  return id;
}

export async function listSheets({ onlyDraft = false } = {}) {
  const database = await initDb();
  const where = onlyDraft ? "where status = 'draft'" : '';
  const res = await database.query(`select * from sheet ${where} order by tanggal desc`);
  return res.values ?? [];
}

export async function getSheet(sheetId) {
  const database = await initDb();
  const res = await database.query('select * from sheet where id = ?', [sheetId]);
  return res.values?.[0] ?? null;
}

// ---- ROUND ----
export async function getOrCreateRound(sheetId, section, roundNumber) {
  const database = await initDb();
  const existing = await database.query(
    'select * from round where sheet_id = ? and section = ? and round_number = ?',
    [sheetId, section, roundNumber]
  );
  if (existing.values?.length) return existing.values[0].id;

  const id = uuid();
  const clientUuid = uuid();
  await insertWithQueue(
    'round',
    ['id', 'client_uuid', 'sheet_id', 'section', 'round_number', 'jam', 'sync_status'],
    [id, clientUuid, sheetId, section, roundNumber, null, 'pending'],
    'round'
  );
  return id;
}

export async function getRound(roundId) {
  const database = await initDb();
  const res = await database.query('select * from round where id = ?', [roundId]);
  return res.values?.[0] ?? null;
}

// jam = "waktu aktual" ronde ini (FR terkait di supabase/schema.sql: "bukan
// hanya Jam: kosong seperti kertas") -- satu jam berlaku untuk seluruh ronde
// (BARAT & TIMUR sekaligus), diisi manual karena bisa beda dari waktu entry
// aplikasi (mis. dicatat di kertas dulu, baru diketik belakangan).
export async function setRoundJam(roundId, jam) {
  const database = await initDb();
  await database.run('update round set jam = ?, sync_status = ? where id = ?', [jam, 'pending', roundId]);

  const row = await database.query('select client_uuid from round where id = ?', [roundId]);
  const clientUuid = row.values[0].client_uuid;
  await database.run(
    `insert into sync_queue (entity_type, client_uuid, operation, payload_json) values (?,?,?,?)`,
    ['round', clientUuid, 'update', JSON.stringify({ client_uuid: clientUuid, jam })]
  );
}

// ---- UNIT STATUS (per sisi — status default NULL / "belum diisi", lihat FR-26a) ----
export async function setUnitStatus({ roundId, unitCode, equipmentId, status, reason }) {
  const database = await initDb();
  const existing = await database.query(
    'select * from unit_status where round_id = ? and ifnull(unit_code,\'\') = ? and ifnull(equipment_id,\'\') = ?',
    [roundId, unitCode ?? '', equipmentId ?? '']
  );

  const now = new Date().toISOString();
  if (existing.values?.length) {
    const rowId = existing.values[0].id;
    await database.run(
      'update unit_status set status = ?, reason = ?, answered_at = ?, sync_status = ? where id = ?',
      [status, reason ?? null, now, 'pending', rowId]
    );
    await database.run(
      `insert into sync_queue (entity_type, client_uuid, operation, payload_json) values (?,?,?,?)`,
      ['unit_status', existing.values[0].client_uuid, 'update',
       JSON.stringify({ id: rowId, client_uuid: existing.values[0].client_uuid, status, reason, answered_at: now })]
    );
    return rowId;
  }

  const id = uuid();
  const clientUuid = uuid();
  await insertWithQueue(
    'unit_status',
    ['id', 'client_uuid', 'round_id', 'unit_code', 'equipment_id', 'status', 'reason', 'answered_at', 'sync_status'],
    [id, clientUuid, roundId, unitCode ?? null, equipmentId ?? null, status, reason ?? null, now, 'pending'],
    'unit_status'
  );
  return id;
}

export async function getUnitStatus(roundId, unitCode, equipmentId = null) {
  const database = await initDb();
  const res = await database.query(
    'select * from unit_status where round_id = ? and ifnull(unit_code,\'\') = ? and ifnull(equipment_id,\'\') = ?',
    [roundId, unitCode ?? '', equipmentId ?? '']
  );
  return res.values?.[0] ?? null; // null = "Belum diisi" (FR-26a) — BUKAN pilihan status, murni belum dijawab
}

// ---- READING ----
// value_numeric untuk field angka (°C), value_boolean untuk Oil Level (OK/Low),
// value_text untuk field bebas seperti Remark. Cuma SATU dari ketiganya yang
// diisi per baris, sesuai data_type milik measurement_point-nya.
export async function saveReading({ roundId, unitStatusId, measurementPointId, valueNumeric, valueBoolean, valueText, recordedBy }) {
  const database = await initDb();
  const existing = await database.query(
    'select * from reading where round_id = ? and measurement_point_id = ? and ifnull(unit_status_id,\'\') = ?',
    [roundId, measurementPointId, unitStatusId ?? '']
  );

  const now = new Date().toISOString();
  const vNum = valueNumeric ?? null;
  const vBool = valueBoolean === undefined ? null : (valueBoolean ? 1 : 0);
  const vText = valueText ?? null;

  if (existing.values?.length) {
    const rowId = existing.values[0].id;
    const clientUuid = existing.values[0].client_uuid;
    await database.run(
      'update reading set value_numeric = ?, value_boolean = ?, value_text = ?, measured_at = ?, sync_status = ? where id = ?',
      [vNum, vBool, vText, now, 'pending', rowId]
    );
    await database.run(
      `insert into sync_queue (entity_type, client_uuid, operation, payload_json) values (?,?,?,?)`,
      ['reading', clientUuid, 'update',
       JSON.stringify({ id: rowId, client_uuid: clientUuid, value_numeric: vNum, value_boolean: vBool, value_text: vText, measured_at: now })]
    );
    return rowId;
  }

  const id = uuid();
  const clientUuid = uuid();
  await insertWithQueue(
    'reading',
    ['id', 'client_uuid', 'round_id', 'unit_status_id', 'measurement_point_id',
     'value_numeric', 'value_boolean', 'value_text', 'measured_at', 'recorded_by', 'is_anomaly', 'sync_status'],
    [id, clientUuid, roundId, unitStatusId ?? null, measurementPointId,
     vNum, vBool, vText, now, recordedBy, 0, 'pending'],
    'reading'
  );
  return id;
}

export async function getReadingsForUnit(roundId, unitStatusId) {
  const database = await initDb();
  const res = await database.query(
    'select * from reading where round_id = ? and ifnull(unit_status_id,\'\') = ?',
    [roundId, unitStatusId ?? '']
  );
  // Kembalikan { measurement_point_id: { value_numeric, value_boolean, value_text } }
  // supaya layar bisa memilih field yang relevan sesuai data_type-nya sendiri.
  const map = {};
  for (const row of res.values ?? []) {
    map[row.measurement_point_id] = {
      value_numeric: row.value_numeric,
      value_boolean: row.value_boolean === null ? null : !!row.value_boolean,
      value_text: row.value_text,
    };
  }
  return map;
}

export async function submitSheet(sheetId) {
  const database = await initDb();
  const now = new Date().toISOString();
  await database.run(
    'update sheet set status = ?, submitted_at = ?, sync_status = ? where id = ?',
    ['submitted', now, 'pending', sheetId]
  );

  const row = await database.query('select client_uuid from sheet where id = ?', [sheetId]);
  const clientUuid = row.values[0].client_uuid;

  await database.run(
    `insert into sync_queue (entity_type, client_uuid, operation, payload_json) values (?,?,?,?)`,
    ['sheet', clientUuid, 'update', JSON.stringify({ client_uuid: clientUuid, status: 'submitted', submitted_at: now })]
  );
}

// ---- JALUR OVERRIDE (FR-15): kirim meski masih ada sisi "Belum diisi" ----
// Cuma boleh dipanggil dari layar yang sudah menegakkan requireRole
// ('foreman','supervisor','admin') — fungsi ini sendiri tidak cek role.
export async function forceSubmitSheet(sheetId, reason, forcedByUserId) {
  const database = await initDb();
  const now = new Date().toISOString();
  await database.run(
    `update sheet set status = ?, submitted_at = ?, force_submitted_by = ?,
     force_submitted_at = ?, force_reason = ?, sync_status = ? where id = ?`,
    ['submitted_incomplete', now, forcedByUserId, now, reason, 'pending', sheetId]
  );

  const row = await database.query('select client_uuid from sheet where id = ?', [sheetId]);
  const clientUuid = row.values[0].client_uuid;

  await database.run(
    `insert into sync_queue (entity_type, client_uuid, operation, payload_json) values (?,?,?,?)`,
    ['sheet', clientUuid, 'update', JSON.stringify({
      client_uuid: clientUuid,
      status: 'submitted_incomplete',
      submitted_at: now,
      force_submitted_by: forcedByUserId,
      force_submitted_at: now,
      force_reason: reason,
    })]
  );
}

// ---- EKSPOR (FR-62/63) ----
// Semua reading milik sheet, lintas section/ronde. measurement_point_id
// belum di-resolve ke label -- itu perlu query terpisah ke Supabase
// (lib/export.js), karena measurement_point tidak di-cache lokal.
export async function getAllReadingsForSheet(sheetId) {
  const database = await initDb();
  const res = await database.query(`
    select r.section, r.round_number, r.jam, us.unit_code, us.status as status_unit,
           rd.measurement_point_id, rd.value_numeric, rd.value_boolean, rd.value_text, rd.recorded_by
    from round r
    join reading rd on rd.round_id = r.id
    left join unit_status us on us.id = rd.unit_status_id
    where r.sheet_id = ?
    order by r.section, r.round_number
  `, [sheetId]);
  return res.values ?? [];
}

// ---- SHEET CONTRIBUTOR (nama crew pengisi) ----
// SEMENTARA: cuma dikirim sekali via operation 'insert' (upsert onConflict
// sheet_id+user_id di sync-engine.js) — belum ada jalur 'update'/'delete'
// individual karena sheet_contributor primary key-nya gabungan, tidak
// punya client_uuid sendiri seperti tabel lain. Kalau nanti perlu edit
// bebas setelah tersimpan, sync-engine.js perlu operasi delete juga.
export async function saveContributors(sheetId, userIds) {
  const database = await initDb();
  for (const userId of userIds) {
    await database.run(
      'insert into sheet_contributor (sheet_id, user_id) values (?, ?)',
      [sheetId, userId]
    );
    await database.run(
      `insert into sync_queue (entity_type, client_uuid, operation, payload_json) values (?,?,?,?)`,
      ['sheet_contributor', uuid(), 'insert', JSON.stringify({ sheet_id: sheetId, user_id: userId })]
    );
  }
}

export async function getContributors(sheetId) {
  const database = await initDb();
  const res = await database.query('select user_id from sheet_contributor where sheet_id = ?', [sheetId]);
  return (res.values ?? []).map((r) => r.user_id);
}

// ---- HAPUS LEMBAR (dipanggil dari sync-engine.js, TIDAK dari layar
// langsung -- lihat deleteSheet() di sana untuk bagian hapus-dari-server) ----
// SQLite lokal TIDAK punya FK constraint/cascade otomatis seperti Postgres,
// jadi anak-anaknya dihapus manual satu-satu di sini, urutan dari yang paling
// dalam ke luar. client_uuid dikumpulkan DULU (sebelum baris dihapus) supaya
// entri sync_queue yang masih nyantol ke baris-baris ini ikut dibuang --
// kalau tidak, sync-engine akan terus mencoba sinkron baris yang sudah tidak
// ada lagi.
export async function deleteSheetLocal(sheetId) {
  const database = await initDb();

  const sheetRow = (await database.query('select client_uuid from sheet where id = ?', [sheetId])).values?.[0];
  if (!sheetRow) return; // sudah tidak ada -- tidak ada yang perlu dilakukan

  const rounds = (await database.query('select id, client_uuid from round where sheet_id = ?', [sheetId])).values ?? [];
  const roundIds = rounds.map((r) => r.id);

  let usUuids = [];
  let readingUuids = [];
  if (roundIds.length > 0) {
    const placeholders = roundIds.map(() => '?').join(',');
    usUuids = ((await database.query(`select client_uuid from unit_status where round_id in (${placeholders})`, roundIds)).values ?? [])
      .map((r) => r.client_uuid);
    readingUuids = ((await database.query(`select client_uuid from reading where round_id in (${placeholders})`, roundIds)).values ?? [])
      .map((r) => r.client_uuid);
    await database.run(`delete from reading where round_id in (${placeholders})`, roundIds);
    await database.run(`delete from unit_status where round_id in (${placeholders})`, roundIds);
    await database.run(`delete from round where sheet_id = ?`, [sheetId]);
  }

  await database.run('delete from sheet_contributor where sheet_id = ?', [sheetId]);
  await database.run('delete from sheet where id = ?', [sheetId]);

  const allUuids = [sheetRow.client_uuid, ...rounds.map((r) => r.client_uuid), ...usUuids, ...readingUuids];
  const ph = allUuids.map(() => '?').join(',');
  await database.run(`delete from sync_queue where client_uuid in (${ph})`, allUuids);
}

// ---- SUBMIT VALIDATION (FR-45: tidak boleh ada status "Belum diisi") ----
// Mengembalikan subset EXPECTED_SIDES yang belum dijawab -- termasuk sisi yang
// round/unit_status-nya belum pernah dibuat sama sekali (belum pernah dibuka),
// bukan cuma yang sudah ada barisnya tapi status-nya NULL. Dipakai layar
// Ringkasan (validasi kirim) dan Daftar Lembar (ringkasan progres per kartu).
export async function getIncompleteSides(sheetId) {
  const database = await initDb();
  const res = await database.query(`
    select r.section, r.round_number, us.unit_code, us.status
    from round r
    left join unit_status us on us.round_id = r.id
    where r.sheet_id = ?
  `, [sheetId]);

  const answered = new Set();
  for (const row of res.values ?? []) {
    if (row.status !== null && row.unit_code) {
      answered.add(`${row.section}|${row.round_number}|${row.unit_code}`);
    }
  }
  return EXPECTED_SIDES.filter((e) => !answered.has(`${e.section}|${e.roundNumber}|${e.unitCode}`));
}
