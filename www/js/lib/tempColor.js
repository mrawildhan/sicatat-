// Warna suhu -- aturan universal SEMENTARA (bukan per titik ukur dari tabel
// `threshold`, yang sudah ada di skema tapi sengaja belum dipakai -- lihat
// admin.js/adminThreshold.js, user minta "jalan dulu" pakai angka tetap ini,
// nanti direvisi jadi per titik ukur kalau perlu): 60-69.9°C = warning
// (kuning), >=70°C = alarm (merah).
export function tempFieldClass(value) {
  if (value === '' || value === null || value === undefined) return '';
  const v = Number(value);
  if (Number.isNaN(v)) return '';
  if (v >= 70) return 'field-alarm';
  if (v >= 60) return 'field-warn';
  return '';
}
