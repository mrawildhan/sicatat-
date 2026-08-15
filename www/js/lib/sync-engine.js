// sync-engine.js — memproses sync_queue lokal ke Supabase.
//
// Alur (Skema-Database-SICATAT-v0.1.md Bagian 4):
//   1. Baca sync_queue FIFO.
//   2. Kirim ke Supabase pakai upsert berdasarkan client_uuid — inilah yang
//      membuat retry aman: kirim ulang tidak pernah membuat baris duplikat.
//   3. Berhasil -> hapus dari antrean, tandai sync_status = 'synced'.
//   4. Gagal -> attempt_count++, simpan last_error, coba lagi nanti.
//
// CATATAN JUJUR: file ini kerangka kerja (skeleton), BUKAN implementasi
// yang sudah teruji end-to-end — karena saya tidak punya akses jaringan
// untuk menguji panggilan Supabase sungguhan dari sini. Sebelum dipakai
// di lapangan, WAJIB diuji manual: matikan WiFi, isi beberapa lembar,
// nyalakan WiFi lagi, pastikan semua masuk ke Supabase tanpa duplikat.

import { supabase } from './supabase-client.js';
import { initDb, getSheet, deleteSheetLocal } from './db.js';

// conflictKey = kolom onConflict untuk upsert (insert). Tiga entitas pertama
// punya client_uuid sendiri sebagai identitas baris. sheet_contributor TIDAK
// — primary key-nya gabungan (sheet_id, user_id), makanya conflictKey beda
// dan entitas ini juga TIDAK PERNAH dikirim dengan operation 'update' (lihat
// db.js saveContributors) sehingga cabang update().eq('client_uuid', ...)
// di bawah tidak pernah tersentuh untuknya.
const TABLE_MAP = {
  sheet: { table: 'sheet', conflictKey: 'client_uuid' },
  round: { table: 'round', conflictKey: 'client_uuid' },
  unit_status: { table: 'unit_status', conflictKey: 'client_uuid' },
  reading: { table: 'reading', conflictKey: 'client_uuid' },
  sheet_contributor: { table: 'sheet_contributor', conflictKey: 'sheet_id,user_id' },
};

// Entitas anak (FK ke induknya) -- tabel & kolom lokal tempat mengecek
// apakah induknya SUDAH tersinkron. round/unit_status/reading punya kolom
// client_uuid sendiri jadi baris lokalnya bisa dicari langsung; sheet_contributor
// tidak (primary key gabungan), jadi induknya diambil dari payload (yang selalu
// utuh karena entitas ini cuma pernah dikirim dengan operation 'insert').
const PARENT_INFO = {
  round: { parentTable: 'sheet', parentField: 'sheet_id' },
  unit_status: { parentTable: 'round', parentField: 'round_id' },
  reading: { parentTable: 'round', parentField: 'round_id' },
  sheet_contributor: { parentTable: 'sheet', parentField: 'sheet_id' },
};

let syncing = false;

export async function syncNow() {
  if (syncing) return; // cegah dua proses sinkron jalan bersamaan
  syncing = true;
  try {
    const database = await initDb();
    const pending = await database.query(
      'select * from sync_queue order by id asc limit 50'
    );

    for (const item of pending.values ?? []) {
      const mapping = TABLE_MAP[item.entity_type];
      if (!mapping) {
        console.warn('sync-engine: entity_type tidak dikenal', item.entity_type);
        continue;
      }
      const { table, conflictKey } = mapping;

      const payload = JSON.parse(item.payload_json);
      const { sync_status, ...serverPayload } = payload;

      // Anak jangan dicoba dulu sebelum induknya SUNGGUH tersinkron -- kalau
      // dipaksa, server selalu tolak dengan FK violation (induknya belum ada
      // sama sekali di server), dan itu kelihatan seperti kegagalan permanen
      // padahal cuma soal urutan/timing. Kalau induknya sudah dipastikan gagal
      // permanen ('conflict', lihat penanganan duplicate key di bawah), anak
      // ini juga MUSTAHIL bisa sinkron -- buang saja, jangan diulang selamanya.
      const parentInfo = PARENT_INFO[item.entity_type];
      if (parentInfo) {
        const parentId = item.entity_type === 'sheet_contributor'
          ? payload.sheet_id
          : (await database.query(
              `select ${parentInfo.parentField} as parent_id from ${table} where client_uuid = ?`,
              [item.client_uuid]
            )).values?.[0]?.parent_id;
        const parentRes = await database.query(
          `select sync_status from ${parentInfo.parentTable} where id = ?`,
          [parentId]
        );
        const parentStatus = parentRes.values?.[0]?.sync_status;
        if (parentStatus === 'conflict') {
          await database.run('delete from sync_queue where id = ?', [item.id]);
          if (item.entity_type !== 'sheet_contributor') {
            await database.run(`update ${table} set sync_status = 'conflict' where client_uuid = ?`, [item.client_uuid]);
          }
          continue;
        }
        if (parentStatus !== 'synced') {
          continue; // coba lagi di putaran sinkron berikutnya, setelah induk beres
        }
      }

      // insert -> upsert (aman diulang, tidak pernah duplikat berkat onConflict).
      // update -> update().eq() sungguhan, BUKAN upsert: payload update cuma
      // berisi kolom yang berubah (mis. submitSheet cuma kirim status +
      // submitted_at, tanpa module_id). upsert() diterjemahkan jadi
      // INSERT..ON CONFLICT DO UPDATE di Postgres — jalur INSERT-nya tetap
      // menuntut semua kolom NOT NULL terisi walau barisnya sudah ada, jadi
      // payload parsial selalu gagal dengan "null value in column ... violates
      // not-null constraint". update().eq() cuma menyentuh kolom yang dikirim.
      const { error } = item.operation === 'insert'
        ? await supabase.from(table).upsert(serverPayload, { onConflict: conflictKey })
        : await supabase.from(table).update(serverPayload).eq('client_uuid', item.client_uuid);

      if (error) {
        // Lembar dengan module+tanggal+shift+tim yang sama sudah ada di server
        // (mis. dibuat dari sesi/perangkat lain). Ini PERMANEN -- diulang
        // sebanyak apa pun hasilnya akan selalu sama. Tandai 'conflict' supaya
        // berhenti dicoba, dan anak-anaknya (round/unit_status/reading) ikut
        // dibuang di putaran berikutnya lewat pengecekan induk di atas.
        const isDuplicateSheet = item.entity_type === 'sheet'
          && error.message.includes('duplicate key value violates unique constraint');
        if (isDuplicateSheet) {
          await database.run(`update sheet set sync_status = 'conflict' where client_uuid = ?`, [item.client_uuid]);
          await database.run('delete from sync_queue where id = ?', [item.id]);
          console.warn('sync-engine: lembar ini sudah ada di server (kemungkinan dibuat dari sesi/perangkat lain) -- ditandai conflict, tidak diulang lagi', item.client_uuid);
          continue;
        }

        await database.run(
          'update sync_queue set attempt_count = attempt_count + 1, last_error = ? where id = ?',
          [error.message, item.id]
        );
        console.error('sync-engine: gagal sinkron', item.entity_type, error.message);
        continue; // lanjut ke item lain, jangan hentikan seluruh antrean
      }

      await database.run('delete from sync_queue where id = ?', [item.id]);
      // sheet_contributor tidak punya kolom sync_status (primary key gabungan,
      // bukan baris tunggal ber-client_uuid) - tidak ada yang perlu ditandai.
      if (item.entity_type !== 'sheet_contributor') {
        await database.run(
          `update ${item.entity_type} set sync_status = 'synced' where client_uuid = ?`,
          [item.client_uuid]
        );
      }
    }
  } finally {
    syncing = false;
  }
}

// Hapus lembar -- satu-satunya tempat yang tahu SQLite lokal DAN Supabase
// sekaligus (db.js sengaja tidak tahu apa-apa soal Supabase, lihat catatan
// di sana). Kalau baris ini sudah pernah tersinkron ('synced'), baris itu
// juga ADA di server dan harus dihapus dari sana dulu (cascade otomatis ke
// round/unit_status/reading/sheet_contributor lewat `on delete cascade` di
// supabase/schema.sql) -- baru boleh dihapus lokal. Kalau belum pernah
// tersinkron ('pending') atau gagal permanen ('conflict'), baris ini sendiri
// tidak pernah diterima server sebagai baris yang sah, jadi cukup dihapus
// lokal saja, tidak ada apa pun untuk dihapus di server.
export async function deleteSheet(sheetId) {
  const sheet = await getSheet(sheetId);
  if (!sheet) return;

  if (sheet.sync_status === 'synced') {
    if (!navigator.onLine) {
      throw new Error('No internet connection -- cannot delete a synced sheet right now.');
    }
    const { error } = await supabase.from('sheet').delete().eq('id', sheetId);
    if (error) throw new Error(`Failed to delete from server: ${error.message}`);
  }

  await deleteSheetLocal(sheetId);
}

// Dipanggil dari app.js saat aplikasi dibuka & saat koneksi kembali online.
export function watchConnectivity() {
  window.addEventListener('online', syncNow);
  // Coba sinkron berkala juga, untuk kasus browser tidak selalu fire 'online' dengan benar.
  setInterval(() => {
    if (navigator.onLine) syncNow();
  }, 60_000);
}
