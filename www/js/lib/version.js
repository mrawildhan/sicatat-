// version.js — FR-56 (info versi baru tersedia) & FR-57 (tolak versi di
// bawah minimum). Sinkronkan APP_VERSION ini manual dengan package.json
// setiap kali rilis versi baru.
//
// PRINSIP PENTING: app ini offline-first. Pengecekan versi TIDAK PERNAH
// boleh memblokir pemakaian app kalau memang lagi offline atau request
// gagal/lambat — fail-open, bukan fail-closed. FR-57 cuma menolak kalau
// KONFIRMASI dari server bilang versi ini di bawah minimum, bukan karena
// tidak berhasil menghubungi server sama sekali.

import { supabase } from './supabase-client.js';

export const APP_VERSION = '0.1.0';

function parseVersion(v) {
  return v.split('.').map((n) => Number(n) || 0);
}

// -1 kalau a < b, 0 kalau sama, 1 kalau a > b
export function compareVersions(a, b) {
  const pa = parseVersion(a);
  const pb = parseVersion(b);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const na = pa[i] ?? 0;
    const nb = pb[i] ?? 0;
    if (na !== nb) return na < nb ? -1 : 1;
  }
  return 0;
}

function withTimeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((resolve) => setTimeout(() => resolve({ data: null, error: new Error('timeout') }), ms)),
  ]);
}

// Selalu resolve (tidak pernah throw) -- kegagalan apa pun berarti
// "tidak ada info versi, anggap aman" (fail-open).
export async function checkAppVersion() {
  try {
    const { data, error } = await withTimeout(
      supabase.from('app_version').select('*').eq('platform', 'android')
        .order('released_at', { ascending: false }).limit(1).maybeSingle(),
      4000
    );
    if (error || !data) return { blocked: false, updateAvailable: false };

    const blocked = compareVersions(APP_VERSION, data.min_version) < 0;
    const updateAvailable = !blocked && compareVersions(APP_VERSION, data.latest_version) < 0;
    return { blocked, updateAvailable, latestVersion: data.latest_version, releaseNotes: data.release_notes };
  } catch {
    return { blocked: false, updateAvailable: false };
  }
}
