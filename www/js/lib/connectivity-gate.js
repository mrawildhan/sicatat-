// connectivity-gate.js — blokir SELURUH app kalau tidak ada koneksi internet.
//
// CATATAN ARSITEKTUR: ini SENGAJA membalikkan sifat "offline-first" yang
// dibangun di sisa app ini (SQLite lokal + sync_queue + pull-sync tetap ada
// & tetap jalan sebagai lapisan ketahanan teknis -- lihat lib/db.js,
// lib/sync-engine.js, lib/pull-sync.js) -- tapi user secara eksplisit minta
// app tidak bisa dipakai SAMA SEKALI tanpa internet, termasuk di tengah
// proses isi form, bukan cuma saat login. Dikonfirmasi user 2026-08-14.
//
// KENAPA BUKAN cuma navigator.onLine + event 'online'/'offline': sudah
// dicoba & terbukti TIDAK cukup di WebView Android (dites di emulator) --
// mematikan WiFi/data via `svc wifi disable`/`svc data disable` bikin fetch
// SUNGGUHAN gagal ("TypeError: Failed to fetch"), tapi WebView-nya tidak
// pernah menembakkan event 'offline' ATAU mengubah navigator.onLine jadi
// false. Jadi overlay-nya tidak pernah muncul walau app SUDAH BENAR-BENAR
// offline -- persis kebalikan dari yang diminta. Solusinya: active probing
// (fetch sungguhan ke server secara berkala), bukan bergantung pada API
// browser yang pasif dan terbukti tidak reliable di platform ini.

import { supabase } from './supabase-client.js';

const PROBE_INTERVAL_MS = 5000;
const PROBE_TIMEOUT_MS = 5000;

let overlay = null;
let probeTimer = null;

function showOverlay() {
  if (overlay) return;
  overlay = document.createElement('div');
  overlay.style.cssText =
    'position:fixed; inset:0; background:#fff; z-index:10000; display:flex; ' +
    'flex-direction:column; align-items:center; justify-content:center; padding:32px; ' +
    'text-align:center; font-family:-apple-system,"Segoe UI",Roboto,Arial,sans-serif;';
  overlay.innerHTML = `
    <div style="font-size:17px; font-weight:700; margin-bottom:10px;">No Internet Connection</div>
    <div style="font-size:13px; color:#5c645c; line-height:1.6; max-width:320px;">
      SICATAT requires an internet connection to run. Please reconnect -- this screen will
      close automatically once you're back online.
    </div>
  `;
  document.body.appendChild(overlay);
}

function hideOverlay() {
  if (!overlay) return;
  overlay.remove();
  overlay = null;
}

// Probe sungguhan ke server -- bukan sekadar baca navigator.onLine (lihat
// catatan di atas kenapa itu tidak cukup). PENTING: pakai client `supabase`
// yang SAMA dipakai seluruh layar app (bukan `fetch` mentah ke root URL) --
// sempat dicoba pakai fetch HEAD ke root domain Supabase dan itu SELALU
// gagal kena CORS (domain root tidak mengirim header CORS untuk request
// sembarangan), which membuat overlay muncul TERUS walau online sungguhan.
// Query kecil (limit 1) ke tabel yang pasti ada & ringan, dengan timeout
// supaya tidak menggantung lama kalau jaringan ada tapi lambat/mati separuh.
async function probe() {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), PROBE_TIMEOUT_MS);
    const { error } = await supabase.from('module').select('id').limit(1).abortSignal(controller.signal);
    clearTimeout(timeoutId);
    if (error) throw error;
    hideOverlay();
  } catch {
    showOverlay();
  }
}

export function watchConnectivityGate() {
  probe();
  probeTimer = setInterval(probe, PROBE_INTERVAL_MS);

  // Tetap pasang listener ini juga -- kalau platform lain (browser desktop,
  // device Android lain) MEMANG menembakkan event ini dengan benar, reaksi
  // jadi instan alih-alih menunggu polling berikutnya. Tidak dihapus, cuma
  // tidak lagi jadi satu-satunya andalan.
  window.addEventListener('online', probe);
  window.addEventListener('offline', showOverlay);
}
