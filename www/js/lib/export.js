// export.js — FR-62 (PDF) & FR-63 (Excel/CSV). Data dasar dari SQLite
// lokal (readings device ini), label titik ukur/equipment/nama di-resolve
// dari Supabase sekali per ekspor (tidak di-cache lokal) -- kalau offline,
// jatuh balik ke kode/id mentah, TIDAK menggagalkan ekspor.

import { jsPDF } from 'jspdf';
import autoTable from 'jspdf-autotable';
import { Filesystem, Directory, Encoding } from '@capacitor/filesystem';
import { Share } from '@capacitor/share';
import { getAllReadingsForSheet } from './db.js';
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
// >=70C merah -- cuma dipakai untuk sel "Nilai" yang satuannya benar-benar
// °C (Oil Level/Remark tidak punya satuan itu, tidak ikut diwarnai). RGB
// selaras dengan --temp-warn-bg/--temp-alarm-bg di style.css -- sengaja pekat
// (bukan pucat) supaya langsung "nabrak mata" tanpa perlu baca satu-satu.
const CELL_COLORS = {
  'field-warn': { fill: [255, 176, 32], text: [61, 36, 0] },    // var(--temp-warn-bg) / --temp-warn-ink
  'field-alarm': { fill: [229, 52, 43], text: [255, 255, 255] }, // var(--temp-alarm-bg) / --temp-alarm-ink
};

export function buildPdf(sheet, sheetContext, contributorNames, rows) {
  const doc = new jsPDF({ orientation: 'landscape' });

  doc.setFontSize(14);
  doc.text('SICATAT — Daily Temperature Check', 14, 15);
  doc.setFontSize(10);
  doc.text(
    `Date: ${sheet.tanggal}    Crew: ${sheetContext.teamName}    Shift: ${sheetContext.shiftName}    ` +
    `Status: ${sheet.status}`,
    14, 22
  );
  doc.text(`Filled By: ${contributorNames.join(', ') || '-'}`, 14, 28);

  const head = [['Section', 'Round', 'Time', 'Side', 'Unit Status', 'Equipment', 'Point', 'Value', 'Unit', 'Recorded By']];
  const body = rows.map((r) => [r.section, r.ronde, r.jam, r.sisi, r.statusUnit, r.equipment, r.titikUkur, r.nilai, r.satuan, r.dicatatOleh]);

  autoTable(doc, {
    head,
    body,
    startY: 34,
    styles: { fontSize: 8, cellPadding: 2 },
    headStyles: { fillColor: [26, 31, 26], textColor: 255 },
    alternateRowStyles: { fillColor: [245, 246, 245] },
    didParseCell: (data) => {
      // Kolom "Nilai" = index 7. Cuma warnai kalau satuannya °C (kolom
      // "Satuan" = index 8) -- Oil Level (OK/Low) & Remark tidak diwarnai.
      if (data.section !== 'body' || data.column.index !== 7) return;
      const satuan = data.row.raw[8];
      if (satuan !== '°C') return;
      const cls = tempFieldClass(data.cell.raw);
      const colors = cls && CELL_COLORS[cls];
      if (colors) {
        data.cell.styles.fillColor = colors.fill;
        data.cell.styles.textColor = colors.text;
        data.cell.styles.fontStyle = 'bold';
      }
    },
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
