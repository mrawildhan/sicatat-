// export.js — FR-62 (PDF) & FR-63 (Excel/CSV). Data dasar dari SQLite
// lokal (readings device ini), label titik ukur di-resolve dari Supabase
// sekali per ekspor (measurement_point tidak di-cache lokal) -- kalau
// offline, label jatuh balik ke kode mentah, TIDAK menggagalkan ekspor.

import { jsPDF } from 'jspdf';
import { Filesystem, Directory, Encoding } from '@capacitor/filesystem';
import { Share } from '@capacitor/share';
import { getAllReadingsForSheet } from './db.js';
import { supabase } from './supabase-client.js';

const SECTION_LABELS = { gearbox_breaker: 'Gb. Breaker', gearbox_sizer: 'Gb. Sizer' };

async function resolvePointLabels(pointIds) {
  const uniqueIds = [...new Set(pointIds)];
  if (uniqueIds.length === 0) return {};
  try {
    const { data, error } = await supabase
      .from('measurement_point').select('id, code, label, unit').in('id', uniqueIds);
    if (error) throw error;
    return Object.fromEntries(data.map((p) => [p.id, p]));
  } catch {
    return {}; // offline atau gagal -- ekspor tetap jalan, label jatuh ke kode
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
  const labels = await resolvePointLabels(readings.map((r) => r.measurement_point_id));

  return readings.map((r) => {
    const point = labels[r.measurement_point_id];
    return {
      section: SECTION_LABELS[r.section] ?? r.section,
      ronde: r.round_number,
      sisi: r.unit_code ?? '',
      titikUkur: point ? point.label : r.measurement_point_id,
      nilai: readingValue(r),
      satuan: point?.unit ?? '',
    };
  });
}

function csvEscape(v) {
  const s = String(v ?? '');
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function buildCsv(sheet, contributorNames, rows) {
  const lines = [
    `Tanggal,${csvEscape(sheet.tanggal)}`,
    `Status,${csvEscape(sheet.status)}`,
    `Crew Pengisi,${csvEscape(contributorNames.join('; '))}`,
    '',
    'Section,Ronde,Sisi,Titik Ukur,Nilai,Satuan',
    ...rows.map((r) => [r.section, r.ronde, r.sisi, r.titikUkur, r.nilai, r.satuan].map(csvEscape).join(',')),
  ];
  return lines.join('\n');
}

export function buildPdf(sheet, contributorNames, rows) {
  const doc = new jsPDF();
  doc.setFontSize(14);
  doc.text('SICATAT — Daily Temperature Check', 14, 16);
  doc.setFontSize(10);
  doc.text(`Tanggal: ${sheet.tanggal}`, 14, 26);
  doc.text(`Status: ${sheet.status}`, 14, 32);
  doc.text(`Crew Pengisi: ${contributorNames.join(', ') || '-'}`, 14, 38);

  let y = 50;
  doc.setFontSize(9);
  doc.text('Section', 14, y);
  doc.text('Ronde', 60, y);
  doc.text('Sisi', 80, y);
  doc.text('Titik Ukur', 105, y);
  doc.text('Nilai', 165, y);
  doc.text('Satuan', 185, y);
  y += 4;
  doc.line(14, y, 196, y);
  y += 5;

  for (const r of rows) {
    if (y > 285) { doc.addPage(); y = 20; }
    doc.text(String(r.section), 14, y);
    doc.text(String(r.ronde), 60, y);
    doc.text(String(r.sisi), 80, y);
    doc.text(String(r.titikUkur), 105, y);
    doc.text(String(r.nilai), 165, y);
    doc.text(String(r.satuan), 185, y);
    y += 6;
  }

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
