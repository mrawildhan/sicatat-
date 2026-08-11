// roster.js — hitung regu bertugas dari roster_anchor (FR-73).
//
// Pola dasar (Skema-Database-SICATAT-v0.1.md, TERKONFIRMASI tidak pernah
// berubah): tiap regu menjalani siklus 9 hari — 3 hari Pagi, 3 hari Malam,
// 3 hari Off — bergiliran antar regu dengan offset 3 hari, sehingga di
// hari mana pun selalu ada tepat satu regu Pagi, satu Malam, satu Off.
//
// urutan_regu[i] mulai Pagi di (tanggal_mula + i*3 hari). Jadi posisi regu
// ke-i pada suatu tanggal, relatif terhadap siklusnya sendiri, adalah
// (hari_selisih - i*3) mod 9:
//   0-2  -> Pagi
//   3-5  -> Malam
//   6-8  -> Off

const MS_PER_DAY = 86_400_000;

function mod(n, m) {
  return ((n % m) + m) % m;
}

// dateStr: 'YYYY-MM-DD'. Mengembalikan kode regu ('A'/'B'/dst) yang piket
// shiftCode ('PAGI'/'MALAM') pada tanggal itu, atau null kalau tidak ada
// yang cocok (harusnya tidak pernah terjadi untuk PAGI/MALAM, cuma OFF yang
// mungkin diminta secara eksplisit).
export function computeTeamCodeForShift(anchor, dateStr, shiftCode) {
  const anchorDate = new Date(anchor.tanggal_mula + 'T00:00:00Z');
  const targetDate = new Date(dateStr + 'T00:00:00Z');
  const hariSelisih = Math.round((targetDate - anchorDate) / MS_PER_DAY);
  const wantedPhase = shiftCode === 'PAGI' ? 0 : shiftCode === 'MALAM' ? 1 : 2;

  for (let i = 0; i < anchor.urutan_regu.length; i++) {
    const posisi = mod(hariSelisih - i * 3, 9);
    const phase = Math.floor(posisi / 3); // 0=Pagi, 1=Malam, 2=Off
    if (phase === wantedPhase) return anchor.urutan_regu[i];
  }
  return null;
}
