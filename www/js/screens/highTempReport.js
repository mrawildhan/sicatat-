// highTempReport.js — Item #4: rekap semua nilai suhu >=60°C, lintas crew &
// rentang tanggal, supaya foreman/supervisor/admin tidak perlu buka satu-satu
// lembar buat lihat ada anomali atau tidak. Pola query meniru buildExportRows
// di adminExport.js (sheet -> round -> unit_status -> reading -> point ->
// equipment -> user, query langsung ke Supabase bukan SQLite lokal, supaya
// lintas regu/device), TAPI reading difilter >=60 di level query -- jauh
// lebih sedikit baris yang perlu ditarik & di-join dibanding ekspor penuh.

import { navigate } from '../lib/router.js';
import { requireRole } from '../lib/auth.js';
import { supabase } from '../lib/supabase-client.js';
import { tempFieldClass } from '../lib/tempColor.js';

const SECTION_LABELS = { gearbox_breaker: 'Gb. Breaker', gearbox_sizer: 'Gb. Sizer' };
// unit_code mentah tetap 'BARAT'/'TIMUR' di data -- cuma label tampilnya West/East.
const SIDE_LABELS = { BARAT: 'West', TIMUR: 'East' };

function formatDateDMY(iso) {
  const [y, m, d] = iso.split('-');
  return `${d}/${m}/${y}`;
}

async function fetchAllIn(table, columns, filterColumn, filterValues, extra) {
  if (filterValues.length === 0) return [];
  const rows = [];
  const pageSize = 1000;
  for (let offset = 0; ; offset += pageSize) {
    let query = supabase.from(table).select(columns).in(filterColumn, filterValues);
    if (extra) query = extra(query);
    const { data, error } = await query.range(offset, offset + pageSize - 1);
    if (error) throw new Error(`Failed to fetch ${table}: ${error.message}`);
    rows.push(...data);
    if (data.length < pageSize) break;
  }
  return rows;
}

async function buildHighTempRows(startDate, endDate, teamId) {
  let query = supabase
    .from('sheet')
    .select('id, tanggal, team:team_id(name), shift:shift_id(code)')
    .gte('tanggal', startDate).lte('tanggal', endDate);
  if (teamId) query = query.eq('team_id', teamId);
  const { data: sheets, error: sheetErr } = await query;
  if (sheetErr) throw new Error(`Failed to fetch sheets: ${sheetErr.message}`);
  if (sheets.length === 0) return [];

  const sheetById = Object.fromEntries(sheets.map((s) => [s.id, s]));
  const sheetIds = sheets.map((s) => s.id);

  const rounds = await fetchAllIn('round', 'id, sheet_id, section, round_number', 'sheet_id', sheetIds);
  const roundById = Object.fromEntries(rounds.map((r) => [r.id, r]));
  const roundIds = rounds.map((r) => r.id);
  if (roundIds.length === 0) return [];

  const unitStatuses = await fetchAllIn('unit_status', 'id, unit_code', 'round_id', roundIds);
  const unitStatusById = Object.fromEntries(unitStatuses.map((u) => [u.id, u]));

  // Filter >=60 DI QUERY -- jauh lebih sedikit baris ditarik dibanding ekspor penuh.
  const readings = await fetchAllIn(
    'reading',
    'round_id, unit_status_id, measurement_point_id, value_numeric, measured_at, recorded_by',
    'round_id', roundIds,
    (q) => q.gte('value_numeric', 60)
  );
  if (readings.length === 0) return [];

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
      crewName: sheet.team?.name ?? '—',
      shiftCode: sheet.shift?.code ?? '',
      section: SECTION_LABELS[round.section] ?? round.section ?? '',
      roundNumber: round.round_number ?? '',
      context: equip ? equip.name : (us?.unit_code ? SIDE_LABELS[us.unit_code] ?? us.unit_code : '—'),
      pointLabel: point.label ?? rd.measurement_point_id,
      value: rd.value_numeric,
      unit: point.unit ?? '',
      recordedBy: user?.name ?? '—',
    };
  });

  rows.sort((a, b) => b.tanggal.localeCompare(a.tanggal) || b.value - a.value);
  return rows;
}

export async function renderHighTempReport(root) {
  if (!requireRole('foreman', 'supervisor', 'admin')) {
    root.innerHTML = `<div class="screen-body"><div class="warn-box">This page is for foreman/supervisor/admin only.</div></div>`;
    return () => {};
  }

  const today = new Date().toISOString().slice(0, 10);
  const firstOfMonth = today.slice(0, 8) + '01';

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
      <button class="btn-back" id="btn-back">← Home</button>
      <div class="topbar-title">High Temperature Report</div>
    </div>
    <div class="screen-body">
      <div class="hint-text">All temperature readings ≥60°C in the selected date range, across crews.</div>
      <div class="field">
        <label>From date</label>
        <input type="date" id="input-start" value="${firstOfMonth}">
      </div>
      <div class="field">
        <label>To date</label>
        <input type="date" id="input-end" value="${today}">
      </div>
      ${teams.length > 0 ? `
      <div class="field">
        <label>Crew</label>
        <select id="input-team">
          <option value="">All Crews</option>
          ${teams.map((t) => `<option value="${t.id}">${t.name}</option>`).join('')}
        </select>
      </div>
      ` : ''}
      <button class="btn-primary" id="btn-load" style="margin-top:10px;">Load</button>
      <div id="report-status" class="hint-text"></div>
      <div id="report-list" style="margin-top:10px;"></div>
    </div>
  `;

  const back = root.querySelector('#btn-back');
  const goBack = () => navigate('/home');
  back.addEventListener('click', goBack);

  const startInput = root.querySelector('#input-start');
  const endInput = root.querySelector('#input-end');
  const teamSelect = root.querySelector('#input-team');
  const loadBtn = root.querySelector('#btn-load');
  const statusEl = root.querySelector('#report-status');
  const listEl = root.querySelector('#report-list');

  function rowHtml(r) {
    const cls = tempFieldClass(r.value);
    return `
      <div class="sheet-card" style="cursor:default;">
        <div>
          <div class="sheet-date">${formatDateDMY(r.tanggal)} • ${r.crewName} • ${r.shiftCode === 'PAGI' ? 'Day' : r.shiftCode === 'MALAM' ? 'Night' : '—'}</div>
          <div class="sheet-shift">${r.section} — Round ${r.roundNumber} · ${r.context} · ${r.pointLabel} · Recorded by ${r.recordedBy}</div>
        </div>
        <span class="temp-badge ${cls}">${r.value}${r.unit}</span>
      </div>
    `;
  }

  const handleLoad = async () => {
    const start = startInput.value;
    const end = endInput.value;
    const teamId = teamSelect?.value || null;
    if (!start || !end) { statusEl.textContent = 'Pick a start and end date first.'; return; }
    if (start > end) { statusEl.textContent = 'Start date cannot be after end date.'; return; }

    loadBtn.disabled = true;
    loadBtn.textContent = 'Loading...';
    statusEl.textContent = '';
    listEl.innerHTML = '';
    try {
      const rows = await buildHighTempRows(start, end, teamId);
      if (rows.length === 0) {
        statusEl.textContent = `No readings ≥60°C between ${formatDateDMY(start)} and ${formatDateDMY(end)}.`;
        return;
      }
      statusEl.textContent = `${rows.length} reading(s) found.`;
      listEl.innerHTML = rows.map(rowHtml).join('');
    } catch (err) {
      statusEl.textContent = `Failed to load: ${err.message}`;
    } finally {
      loadBtn.disabled = false;
      loadBtn.textContent = 'Load';
    }
  };
  loadBtn.addEventListener('click', handleLoad);

  return () => {
    back.removeEventListener('click', goBack);
    loadBtn.removeEventListener('click', handleLoad);
  };
}
