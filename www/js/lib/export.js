// export.js — FR-62 (PDF) & FR-63 (Excel/CSV). Data dasar dari SQLite
// lokal (readings device ini), label titik ukur/equipment/nama di-resolve
// dari Supabase sekali per ekspor (tidak di-cache lokal) -- kalau offline,
// jatuh balik ke kode/id mentah, TIDAK menggagalkan ekspor.

import { jsPDF } from 'jspdf';
import autoTable from 'jspdf-autotable';
import { Filesystem, Directory, Encoding } from '@capacitor/filesystem';
import { Share } from '@capacitor/share';
import { getAllReadingsForSheet, getAllUnitStatusForSheet } from './db.js';
import { supabase } from './supabase-client.js';
import { tempFieldClass } from './tempColor.js';

const SECTION_LABELS = { gearbox_breaker: 'Gb. Breaker', gearbox_sizer: 'Gb. Sizer' };
// unit_code mentah tetap 'BARAT'/'TIMUR' di data -- cuma label tampilnya West/East.
const SIDE_LABELS = { BARAT: 'West', TIMUR: 'East' };
const STATUS_UNIT_LABELS = {
  beroperasi: 'Operating',
  tidak_beroperasi: 'Not operating',
  tidak_dapat_diakses: 'Not accessible',
};

async function resolvePointLabels(pointIds) {
  const uniqueIds = [...new Set(pointIds)];
  if (uniqueIds.length === 0) return {};
  try {
    const { data, error } = await supabase
      .from('measurement_point').select('id, code, label, unit, equipment_id').in('id', uniqueIds);
    if (error) throw error;
    return Object.fromEntries(data.map((p) => [p.id, p]));
  } catch {
    return {}; // offline atau gagal -- ekspor tetap jalan, label jatuh ke kode
  }
}

async function resolveEquipmentNames(equipmentIds) {
  const uniqueIds = [...new Set(equipmentIds.filter(Boolean))];
  if (uniqueIds.length === 0) return {};
  try {
    const { data, error } = await supabase.from('equipment').select('id, name').in('id', uniqueIds);
    if (error) throw error;
    return Object.fromEntries(data.map((e) => [e.id, e.name]));
  } catch {
    return {};
  }
}

// Crew & Shift ditampilkan sebagai nama, bukan uuid mentah, di kop CSV/PDF.
export async function resolveSheetContext(sheet) {
  try {
    const [{ data: team }, { data: shift }] = await Promise.all([
      supabase.from('team').select('name').eq('id', sheet.team_id).single(),
      supabase.from('shift').select('name').eq('id', sheet.shift_id).single(),
    ]);
    return { teamName: team?.name ?? '—', shiftName: shift?.name ?? '—' };
  } catch {
    return { teamName: '—', shiftName: '—' };
  }
}

function readingValue(row) {
  if (row.value_numeric !== null) return String(row.value_numeric);
  if (row.value_boolean !== null) return row.value_boolean ? 'OK' : 'Low';
  if (row.value_text !== null) return row.value_text;
  return '';
}

export async function resolveContributorNames(userIds) {
  if (userIds.length === 0) return [];
  try {
    const { data, error } = await supabase.from('app_user').select('id, name').in('id', userIds);
    if (error) throw error;
    return data.map((u) => u.name);
  } catch {
    return userIds; // offline -- tampilkan id mentah daripada gagal total
  }
}

export async function buildExportRows(sheetId) {
  const readings = await getAllReadingsForSheet(sheetId);
  const points = await resolvePointLabels(readings.map((r) => r.measurement_point_id));
  const equipmentNames = await resolveEquipmentNames(Object.values(points).map((p) => p.equipment_id));

  const recordedByIds = [...new Set(readings.map((r) => r.recorded_by).filter(Boolean))];
  const recordedByNames = recordedByIds.length ? await resolveContributorNamesMap(recordedByIds) : {};

  return readings.map((r) => {
    const point = points[r.measurement_point_id];
    return {
      section: SECTION_LABELS[r.section] ?? r.section,
      ronde: r.round_number,
      jam: r.jam ?? '',
      sisi: r.unit_code ? SIDE_LABELS[r.unit_code] ?? r.unit_code : '',
      statusUnit: STATUS_UNIT_LABELS[r.status_unit] ?? (r.status_unit ?? ''),
      equipment: point?.equipment_id ? (equipmentNames[point.equipment_id] ?? '') : '',
      titikUkur: point ? point.label : r.measurement_point_id,
      nilai: readingValue(r),
      satuan: point?.unit ?? '',
      dicatatOleh: recordedByNames[r.recorded_by] ?? '',
    };
  });
}

async function resolveContributorNamesMap(userIds) {
  try {
    const { data, error } = await supabase.from('app_user').select('id, name').in('id', userIds);
    if (error) throw error;
    return Object.fromEntries(data.map((u) => [u.id, u.name]));
  } catch {
    return {};
  }
}

function csvEscape(v) {
  const s = String(v ?? '');
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function buildCsv(sheet, sheetContext, contributorNames, rows) {
  const lines = [
    `SICATAT - Daily Temperature Check`,
    `Date,${csvEscape(sheet.tanggal)}`,
    `Crew,${csvEscape(sheetContext.teamName)}`,
    `Shift,${csvEscape(sheetContext.shiftName)}`,
    `Sheet Status,${csvEscape(sheet.status)}`,
    `Filled By,${csvEscape(contributorNames.join('; '))}`,
    '',
    'Section,Round,Time,Side,Unit Status,Equipment,Point,Value,Unit,Recorded By',
    ...rows.map((r) => [
      r.section, r.ronde, r.jam, r.sisi, r.statusUnit, r.equipment, r.titikUkur, r.nilai, r.satuan, r.dicatatOleh,
    ].map(csvEscape).join(',')),
  ];
  return lines.join('\n');
}

// Warna suhu sama seperti di layar input (lib/tempColor.js): 60-69.9C amber,
// >=70C merah. RGB selaras dengan --temp-warn-bg/--temp-alarm-bg di
// style.css -- sengaja pekat (bukan pucat) supaya langsung "nabrak mata"
// tanpa perlu baca satu-satu.
const CELL_COLORS = {
  'field-warn': { fill: [255, 176, 32], text: [61, 36, 0] },    // var(--temp-warn-bg) / --temp-warn-ink
  'field-alarm': { fill: [229, 52, 43], text: [255, 255, 255] }, // var(--temp-alarm-bg) / --temp-alarm-ink
};

// 4 titik ukur gearbox baku -- HARUS sama persis dengan measurement_point.label
// di Supabase (Title Case: "Low Speed"/"High Speed"/"Input Shaft"), BUKAN
// label lokal di breakerInput.js (POINT_CODES pakai sentence case buat UI --
// beda casing dari DB, pernah bikin 3 dari 4 titik hilang diam-diam dari PDF
// karena string-match di buildGearboxBody gagal). SELALU ditampilkan di
// laporan (walau kosong, ditulis "—") supaya pembaca tahu itu memang belum
// diisi, bukan diam-diam hilang.
const GEARBOX_POINT_LABELS = ['Low Speed', 'Intermediate', 'High Speed', 'Input Shaft'];

const STATUS_DISPLAY = {
  beroperasi: 'Operating',
  tidak_beroperasi: 'Not operating',
  tidak_dapat_diakses: 'Not accessible',
};

// Sel angka °C diwarnai (fill+text pekat, lihat CELL_COLORS); sel lain
// (OK/Low, teks bebas, atau kosong) ditampilkan apa adanya, "—" kalau kosong.
function pdfCell(value, satuan) {
  if (value === '' || value === null || value === undefined) return '—';
  if (satuan !== '°C') return String(value);
  const cls = tempFieldClass(Number(value));
  const colors = cls && CELL_COLORS[cls];
  if (!colors) return String(value);
  return { content: String(value), styles: { fillColor: colors.fill, textColor: colors.text, fontStyle: 'bold' } };
}

// Tabel "Equipment Readings" -- 1 baris per (equipment, field), Round 1 &
// Round 2 sebagai KOLOM (bukan baris terpisah) supaya lebih ringkas. Semua
// field SELALU tampil kecuali "Remark" yang boleh disembunyikan kalau kedua
// ronde memang kosong (satu-satunya field yang murni catatan opsional).
function buildEquipmentBody(rows) {
  const groups = new Map();
  const order = [];
  for (const r of rows) {
    if (!r.equipment) continue; // baris gearbox, bukan equipment
    const key = `${r.equipment}|${r.titikUkur}`;
    if (!groups.has(key)) {
      const unitSuffix = r.satuan ? ` (${r.satuan})` : '';
      groups.set(key, {
        label: `${r.equipment} — ${r.titikUkur}${unitSuffix}`,
        satuan: r.satuan,
        isRemark: r.titikUkur === 'Remark',
        r1: '', r2: '',
      });
      order.push(key);
    }
    const g = groups.get(key);
    if (r.ronde === 1) g.r1 = r.nilai;
    else if (r.ronde === 2) g.r2 = r.nilai;
  }
  return order
    .map((k) => groups.get(k))
    .filter((g) => !(g.isRemark && !g.r1 && !g.r2))
    .map((g) => [g.label, pdfCell(g.r1, g.satuan), pdfCell(g.r2, g.satuan)]);
}

// Tabel "Gearbox Temperature" -- dikelompokkan per (section x sisi), diawali
// baris Status (dari unitStatuses, BUKAN dari rows -- lihat catatan
// getAllUnitStatusForSheet soal kenapa sumbernya beda), lalu 4 titik ukur
// baku. rows dan unitStatuses SUDAH pakai label tampil yang sama
// (SECTION_LABELS/SIDE_LABELS), jadi bisa digabung langsung pakai label itu
// sebagai kunci, tidak perlu balik ke kode mentah.
function buildGearboxBody(rows, unitStatuses) {
  const groups = new Map();
  const order = [];

  function ensureGroup(sectionLabel, sideLabel) {
    const key = `${sectionLabel}|${sideLabel}`;
    if (!groups.has(key)) {
      groups.set(key, { label: `${sectionLabel} — ${sideLabel}`, status: { r1: '', r2: '' }, points: new Map() });
      order.push(key);
    }
    return groups.get(key);
  }

  for (const us of unitStatuses) {
    const sectionLabel = SECTION_LABELS[us.section] ?? us.section;
    const sideLabel = SIDE_LABELS[us.unit_code] ?? us.unit_code;
    const g = ensureGroup(sectionLabel, sideLabel);
    const display = STATUS_DISPLAY[us.status] ?? (us.status ?? '');
    if (us.round_number === 1) g.status.r1 = display;
    else if (us.round_number === 2) g.status.r2 = display;
  }

  for (const r of rows) {
    if (!r.sisi) continue; // baris equipment, bukan gearbox
    const g = ensureGroup(r.section, r.sisi); // r.section & r.sisi sudah label tampil
    if (!g.points.has(r.titikUkur)) g.points.set(r.titikUkur, { satuan: r.satuan, r1: '', r2: '' });
    const p = g.points.get(r.titikUkur);
    if (r.ronde === 1) p.r1 = r.nilai;
    else if (r.ronde === 2) p.r2 = r.nilai;
  }

  const body = [];
  for (const key of order) {
    const g = groups.get(key);
    body.push([`${g.label} — Status`, g.status.r1 || '—', g.status.r2 || '—']);
    for (const pointLabel of GEARBOX_POINT_LABELS) {
      const p = g.points.get(pointLabel);
      const satuan = p?.satuan ?? '°C';
      body.push([`${g.label} — ${pointLabel} (${satuan})`, pdfCell(p?.r1 ?? '', satuan), pdfCell(p?.r2 ?? '', satuan)]);
    }
  }
  return body;
}

// Layout 2 kolom BERDAMPINGAN (Equipment kiri, Gearbox kanan), bukan
// ditumpuk vertikal -- landscape A4 lebar (297mm) tapi pendek (210mm);
// ditumpuk vertikal kepotong 2 halaman (diverifikasi lewat skrip Node
// standalone sebelum kode ini ditulis), berdampingan muat 1 halaman dengan
// sisa ruang aman. font 7.5pt/padding 1.5mm dipilih dari validasi yang sama.
export async function buildPdf(sheet, sheetContext, contributorNames, rows) {
  const unitStatuses = await getAllUnitStatusForSheet(sheet.id);

  const doc = new jsPDF({ orientation: 'landscape' });

  doc.setFontSize(13);
  doc.text('SICATAT — Daily Temperature Check', 10, 12);
  doc.setFontSize(8);
  doc.text(
    `Date: ${sheet.tanggal}    Crew: ${sheetContext.teamName}    Shift: ${sheetContext.shiftName}    ` +
    `Status: ${sheet.status}`,
    10, 17
  );
  doc.text(`Filled By: ${contributorNames.join(', ') || '-'}`, 10, 21);

  const LEFT_X = 10, LEFT_W = 140, RIGHT_X = 155, RIGHT_W = 132, START_Y = 27;
  const tableStyle = {
    styles: { fontSize: 7.5, cellPadding: 1.5 },
    headStyles: { fillColor: [26, 31, 26], textColor: 255, fontSize: 8 },
    alternateRowStyles: { fillColor: [245, 246, 245] },
  };

  doc.setFontSize(9);
  doc.text('Equipment Readings', LEFT_X, START_Y - 2);
  doc.text('Gearbox Temperature', RIGHT_X, START_Y - 2);

  autoTable(doc, {
    ...tableStyle,
    head: [['Equipment / Field', 'R1', 'R2']],
    body: buildEquipmentBody(rows),
    startY: START_Y,
    columnStyles: { 0: { cellWidth: LEFT_W - 30 }, 1: { cellWidth: 15, halign: 'center' }, 2: { cellWidth: 15, halign: 'center' } },
    margin: { left: LEFT_X },
    tableWidth: LEFT_W,
  });

  autoTable(doc, {
    ...tableStyle,
    head: [['Section / Point', 'R1', 'R2']],
    body: buildGearboxBody(rows, unitStatuses),
    startY: START_Y,
    columnStyles: { 0: { cellWidth: RIGHT_W - 30 }, 1: { cellWidth: 15, halign: 'center' }, 2: { cellWidth: 15, halign: 'center' } },
    margin: { left: RIGHT_X },
    tableWidth: RIGHT_W,
  });

  return doc;
}

// jsPDF v4 TIDAK punya output type 'base64' (bukan bagian API sama sekali --
// cuma 'datauristring' yang ada). 'datauristring' balikin data URI lengkap
// (data:application/pdf;filename=...;base64,XXXX) -- ambil bagian base64
// murninya setelah koma pertama.
export function pdfToBase64(doc) {
  return doc.output('datauristring').split(',')[1];
}

// Blob+<a download> di WebView Capacitor (androidScheme:'https') terbukti
// bikin CRASH TOTAL emulator saat dicoba -- bukan sekadar gagal diam-diam.
// Filesystem native (tulis ke Cache) + Share sheet Android jauh lebih aman:
// user pilih sendiri mau simpan ke mana (Files, Drive, WhatsApp, dst).
export async function saveAndShareText(text, filename, mimeType) {
  await Filesystem.writeFile({ path: filename, data: text, directory: Directory.Cache, encoding: Encoding.UTF8 });
  const { uri } = await Filesystem.getUri({ path: filename, directory: Directory.Cache });
  await Share.share({ title: filename, url: uri });
}

export async function saveAndShareBase64(base64Data, filename) {
  await Filesystem.writeFile({ path: filename, data: base64Data, directory: Directory.Cache });
  const { uri } = await Filesystem.getUri({ path: filename, directory: Directory.Cache });
  await Share.share({ title: filename, url: uri });
}
