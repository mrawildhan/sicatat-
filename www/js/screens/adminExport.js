import { navigate } from '../lib/router.js';
import { requireRole } from '../lib/auth.js';
import { supabase } from '../lib/supabase-client.js';
import { saveAndShareText } from '../lib/export.js';

const SECTION_LABELS = { gearbox_breaker: 'Gb. Breaker', gearbox_sizer: 'Gb. Sizer' };

function csvEscape(v) {
  const s = String(v ?? '');
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function readingValue(row) {
  if (row.value_numeric !== null) return String(row.value_numeric);
  if (row.value_boolean !== null) return row.value_boolean ? 'OK' : 'Low';
  if (row.value_text !== null) return row.value_text;
  return '';
}

// Ambil SEMUA baris cocok filter `in`, bukan cuma 1000 pertama (limit default
// PostgREST) -- rentang sebulan bisa saja lebih dari itu kalau lembarnya banyak.
async function fetchAllIn(table, columns, filterColumn, filterValues) {
  if (filterValues.length === 0) return [];
  const rows = [];
  const pageSize = 1000;
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await supabase
      .from(table).select(columns).in(filterColumn, filterValues)
      .range(offset, offset + pageSize - 1);
    if (error) throw new Error(`Gagal ambil ${table}: ${error.message}`);
    rows.push(...data);
    if (data.length < pageSize) break;
  }
  return rows;
}

// Query langsung ke Supabase (BUKAN SQLite lokal) -- rentang tanggal mencakup
// lembar dari semua regu/perangkat, bukan cuma yang kebetulan pernah dibuka
// di HP ini. Dipecah jadi beberapa query + join manual di JS (bukan satu
// query nested) karena filter tanggal ada di `sheet`, sementara PostgREST
// tidak bisa filter kolom di embed dua-level-dalam (reading -> round -> sheet)
// dengan andal.
async function buildExportRows(startDate, endDate, teamId) {
  let query = supabase
    .from('sheet')
    .select('id, tanggal, status, team:team_id(name), shift:shift_id(name)')
    .gte('tanggal', startDate).lte('tanggal', endDate);
  if (teamId) query = query.eq('team_id', teamId);
  const { data: sheets, error: sheetErr } = await query;
  if (sheetErr) throw new Error(`Gagal ambil lembar: ${sheetErr.message}`);
  if (sheets.length === 0) return { rows: [], sheetCount: 0 };

  const sheetById = Object.fromEntries(sheets.map((s) => [s.id, s]));
  const sheetIds = sheets.map((s) => s.id);

  const rounds = await fetchAllIn('round', 'id, sheet_id, section, round_number, jam', 'sheet_id', sheetIds);
  const roundById = Object.fromEntries(rounds.map((r) => [r.id, r]));
  const roundIds = rounds.map((r) => r.id);

  const unitStatuses = await fetchAllIn('unit_status', 'id, unit_code, status', 'round_id', roundIds);
  const unitStatusById = Object.fromEntries(unitStatuses.map((u) => [u.id, u]));

  const readings = await fetchAllIn(
    'reading',
    'round_id, unit_status_id, measurement_point_id, value_numeric, value_boolean, value_text, measured_at, recorded_by',
    'round_id', roundIds
  );

  const pointIds = [...new Set(readings.map((r) => r.measurement_point_id))];
  const points = await fetchAllIn('measurement_point', 'id, label, unit, equipment_id', 'id', pointIds);
  const pointById = Object.fromEntries(points.map((p) => [p.id, p]));

  const equipIds = [...new Set(points.map((p) => p.equipment_id).filter(Boolean))];
  const equipRows = await fetchAllIn('equipment', 'id, name', 'id', equipIds);
  const equipById = Object.fromEntries(equipRows.map((e) => [e.id, e]));

  const userIds = [...new Set(readings.map((r) => r.recorded_by).filter(Boolean))];
  const users = await fetchAllIn('app_user', 'id, name', 'id', userIds);
  const userById = Object.fromEntries(users.map((u) => [u.id, u]));

  const rows = readings.map((rd) => {
    const round = roundById[rd.round_id] ?? {};
    const sheet = sheetById[round.sheet_id] ?? {};
    const us = rd.unit_status_id ? unitStatusById[rd.unit_status_id] : null;
    const point = pointById[rd.measurement_point_id] ?? {};
    const equip = point.equipment_id ? equipById[point.equipment_id] : null;
    const user = rd.recorded_by ? userById[rd.recorded_by] : null;

    return {
      tanggal: sheet.tanggal ?? '',
      regu: sheet.team?.name ?? '',
      shift: sheet.shift?.name ?? '',
      section: SECTION_LABELS[round.section] ?? round.section ?? '',
      ronde: round.round_number ?? '',
      jam: round.jam ?? '',
      sisi: us?.unit_code ?? '',
      statusUnit: us?.status ?? '',
      equipment: equip?.name ?? '',
      titikUkur: point.label ?? rd.measurement_point_id,
      nilai: readingValue(rd),
      satuan: point.unit ?? '',
      dicatatOleh: user?.name ?? '',
      statusLembar: sheet.status ?? '',
    };
  });

  rows.sort((a, b) => a.tanggal.localeCompare(b.tanggal) || a.section.localeCompare(b.section) || a.ronde - b.ronde);
  return { rows, sheetCount: sheets.length };
}

function buildCsv(rows) {
  const lines = [
    'Tanggal,Regu,Shift,Section,Ronde,Jam,Sisi,Status Unit,Equipment,Titik Ukur,Nilai,Satuan,Dicatat Jam,Dicatat Oleh,Status Lembar',
    ...rows.map((r) => [
      r.tanggal, r.regu, r.shift, r.section, r.ronde, r.jam, r.sisi, r.statusUnit,
      r.equipment, r.titikUkur, r.nilai, r.satuan, r.measured_at ?? '', r.dicatatOleh, r.statusLembar,
    ].map(csvEscape).join(',')),
  ];
  return lines.join('\n');
}

export async function renderAdminExport(root) {
  if (!requireRole('admin')) {
    root.innerHTML = `<div class="screen-body"><div class="warn-box">Halaman ini khusus admin.</div></div>`;
    return () => {};
  }

  const today = new Date().toISOString().slice(0, 10);
  const firstOfMonth = today.slice(0, 8) + '01';

  // Gagal diam-diam kalau offline -- filter regu cuma tidak muncul, ekspor
  // tetap bisa jalan tanpa filter (lintas semua regu, seperti sebelumnya).
  let teams = [];
  try {
    const { data, error } = await supabase.from('team').select('id, name').order('code');
    if (error) throw error;
    teams = data ?? [];
  } catch {
    teams = [];
  }

  root.innerHTML = `
    <div class="topbar">
      <button class="btn-back" id="btn-back">← Kelola Master Data</button>
      <div class="topbar-title">Ekspor Rentang Tanggal</div>
    </div>
    <div class="screen-body">
      <div class="hint-text">Tarik semua data pembacaan (lintas regu &amp; perangkat) dalam rentang tanggal jadi satu file CSV, untuk dianalisa di Excel.</div>
      <div class="field">
        <label>Dari tanggal</label>
        <input type="date" id="input-start" value="${firstOfMonth}">
      </div>
      <div class="field">
        <label>Sampai tanggal</label>
        <input type="date" id="input-end" value="${today}">
      </div>
      ${teams.length > 0 ? `
      <div class="field">
        <label>Regu</label>
        <select id="input-team">
          <option value="">Semua Regu</option>
          ${teams.map((t) => `<option value="${t.id}">${t.name}</option>`).join('')}
        </select>
      </div>
      ` : ''}
      <button class="btn-primary" id="btn-export" style="margin-top:10px;">Ekspor CSV</button>
      <div id="export-status" class="hint-text"></div>
    </div>
  `;

  const back = root.querySelector('#btn-back');
  const goBack = () => navigate('/admin');
  back.addEventListener('click', goBack);

  const startInput = root.querySelector('#input-start');
  const endInput = root.querySelector('#input-end');
  const teamSelect = root.querySelector('#input-team');
  const exportBtn = root.querySelector('#btn-export');
  const statusEl = root.querySelector('#export-status');

  const handleExport = async () => {
    const start = startInput.value;
    const end = endInput.value;
    const teamId = teamSelect?.value || null;
    if (!start || !end) { statusEl.textContent = 'Isi dulu tanggal mulai & akhir.'; return; }
    if (start > end) { statusEl.textContent = 'Tanggal mulai tidak boleh setelah tanggal akhir.'; return; }

    exportBtn.disabled = true;
    exportBtn.textContent = 'Mengambil data...';
    statusEl.textContent = '';
    try {
      const { rows, sheetCount } = await buildExportRows(start, end, teamId);
      if (rows.length === 0) {
        statusEl.textContent = `Tidak ada data lembar antara ${start} dan ${end}.`;
        return;
      }
      const teamSuffix = teamId ? `-${teamSelect.options[teamSelect.selectedIndex].textContent.replace(/\s+/g, '_')}` : '';
      const csv = buildCsv(rows);
      await saveAndShareText(csv, `sicatat-export-${start}_${end}${teamSuffix}.csv`);
      statusEl.textContent = `${sheetCount} lembar, ${rows.length} baris data berhasil diekspor.`;
    } catch (err) {
      statusEl.textContent = `Gagal ekspor: ${err.message}`;
    } finally {
      exportBtn.disabled = false;
      exportBtn.textContent = 'Ekspor CSV';
    }
  };
  exportBtn.addEventListener('click', handleExport);

  return () => {
    back.removeEventListener('click', goBack);
    exportBtn.removeEventListener('click', handleExport);
  };
}
