import { listSheets, createSheet, getIncompleteSides } from '../lib/db.js';
import { getCurrentUser, requireRole } from '../lib/auth.js';
import { navigate } from '../lib/router.js';
import { supabase } from '../lib/supabase-client.js';
import { computeTeamCodeForShift } from '../lib/roster.js';
import { pullTeamDrafts } from '../lib/pull-sync.js';

const TEMPLATE_VERSION = 'v0.4';

const SHIFT_LABELS = { PAGI: 'Day', MALAM: 'Night' };
function shiftLabel(code) {
  return SHIFT_LABELS[code] ?? code;
}

function formatDateDMY(iso) {
  const [y, m, d] = iso.split('-');
  return `${d}/${m}/${y}`;
}

async function resolveModuleId() {
  const { data, error } = await supabase
    .from('module').select('id').eq('code', 'temperature_check').single();
  if (error) throw new Error(`Failed to fetch module: ${error.message}`);
  return data.id;
}

// Item #1 (2026-08-14): satu shift = satu regu bertugas (sesuai roster).
// Kalau Regu A sudah punya lembar Day di tanggal X, regu LAIN tidak boleh
// ikut bikin lembar Day juga di tanggal yang sama -- dianggap data dobel.
// Baris milik REGU SENDIRI dikecualikan (itu bukan "dobel", itu lanjutan
// pekerjaan sendiri -- dedupe-nya sudah ditangani createSheet() di db.js).
// Kembalikan Map<shift_id, namaRegu> utk shift yang "sudah dipakai regu lain".
async function getTakenShifts(moduleId, tanggal, ownTeamId) {
  if (!moduleId || !tanggal) return new Map();
  try {
    const { data, error } = await supabase
      .from('sheet')
      .select('shift_id, team_id, team:team_id(name)')
      .eq('module_id', moduleId)
      .eq('tanggal', tanggal);
    if (error) throw error;
    const taken = new Map();
    for (const row of data ?? []) {
      if (ownTeamId && row.team_id === ownTeamId) continue; // regu sendiri, bukan dobel
      if (!taken.has(row.shift_id)) taken.set(row.shift_id, row.team?.name ?? 'another crew');
    }
    return taken;
  } catch {
    return new Map(); // gagal/offline -- jangan blokir, biar tetap bisa dipakai
  }
}

// Regu: crew & foreman SELALU punya team_id sendiri (wajib diisi di
// app_user, lihat skema) — pakai itu LANGSUNG, tidak perlu hitung rotasi
// sama sekali. Cuma supervisor/admin (team_id null, lintas tim) yang
// butuh ditebak dari roster_anchor (perlu shiftCode untuk itu, makanya
// tetap parameter meski shift sekarang dipilih manual, bukan dari jam).
async function resolveTeam(user, shiftCode) {
  let teamId = user.team_id;

  if (!teamId) {
    const { data: anchor } = await supabase
      .from('roster_anchor').select('*').eq('is_active', true)
      .order('tanggal_mula', { ascending: false }).limit(1).maybeSingle();

    if (anchor) {
      const today = new Date().toISOString().slice(0, 10);
      const teamCode = computeTeamCodeForShift(anchor, today, shiftCode);
      if (teamCode) {
        const { data: team } = await supabase.from('team').select('id').eq('code', teamCode).single();
        if (team) teamId = team.id;
      }
    }
  }

  if (!teamId) {
    const { data: team, error: teamError } = await supabase
      .from('team').select('id').order('code').limit(1).single();
    if (teamError) throw new Error(`Failed to fetch crew: ${teamError.message}`);
    teamId = team.id;
  }

  return teamId;
}

export async function renderSheetList(root) {
  const user = getCurrentUser();

  // Tarik draft dari server dulu (kalau online) -- supaya lembar yang mulai
  // diisi dari HP orang lain muncul di sini juga, bukan bikin duplikat.
  // admin/supervisor/foreman tarik draft SEMUA regu (mereka boleh lihat &
  // hapus lembar regu mana pun -- lihat summary.js canDelete); crew cuma
  // tarik draft regunya sendiri.
  try {
    if (requireRole('admin', 'supervisor', 'foreman')) {
      await pullTeamDrafts(null);
    } else if (user.team_id) {
      await pullTeamDrafts(user.team_id);
    }
  } catch (err) {
    console.warn('sheetList: gagal tarik draft', err.message);
  }

  const sheets = await listSheets();

  // Buat cek ketersediaan shift (Item #1) -- gagal diam-diam kalau offline,
  // toggle shift tetap semua aktif (tidak memblokir kalau tidak bisa dicek).
  let moduleId = null;
  try {
    moduleId = await resolveModuleId();
  } catch {
    moduleId = null;
  }

  // Daftar shift buat picker Siang/Malam & buat label kartu riwayat. Kalau
  // offline saat cuma MELIHAT daftar (bukan bikin baru), gagal diam-diam --
  // kartu tetap tampil, cuma tanpa label shift.
  let shifts = [];
  try {
    const { data, error } = await supabase.from('shift').select('id, code').order('code');
    if (error) throw error;
    // .order('code') alfabetis taruh MALAM sebelum PAGI (M < P) -- urutkan
    // ulang eksplisit supaya Day SELALU tampil duluan di toggle (Item 8).
    shifts = (data ?? []).sort((a, b) => (a.code === 'PAGI' ? 0 : 1) - (b.code === 'PAGI' ? 0 : 1));
  } catch {
    shifts = [];
  }
  const shiftCodeById = Object.fromEntries(shifts.map((s) => [s.id, s.code]));

  // Daftar crew buat filter -- sama seperti shift, gagal diam-diam kalau offline
  // (filter crew cuma tidak muncul, bukan mengganggu daftar lembar yang tetap tampil).
  let teams = [];
  try {
    const { data, error } = await supabase.from('team').select('id, name, code').order('code');
    if (error) throw error;
    teams = data ?? [];
  } catch {
    teams = [];
  }
  const teamCodeById = Object.fromEntries(teams.map((t) => [t.id, t.code]));

  const currentHourCode = new Date().getHours() >= 7 && new Date().getHours() < 19 ? 'PAGI' : 'MALAM';
  let selectedShiftId = shifts.find((s) => s.code === currentHourCode)?.id ?? shifts[0]?.id ?? null;

  root.innerHTML = `
    <div class="topbar">
      <button class="btn-back" id="btn-back">← Temperature</div>
      <div class="topbar-title">Daily Temperature Check</div>
    </div>
    <div class="screen-body">
      <div class="field">
        <label>Sheet date</label>
        <input type="date" id="input-tanggal" value="${new Date().toISOString().slice(0, 10)}">
      </div>
      <div class="field">
        <label>Shift</label>
        <div class="side-toggle" id="shift-toggle">
          ${shifts
            .map((s) => `<button type="button" data-shift-id="${s.id}" class="${s.id === selectedShiftId ? 'active' : ''}">${shiftLabel(s.code)}</button>`)
            .join('')}
        </div>
        <div id="shift-availability-hint" class="hint-text" style="margin-top:6px; text-align:left;"></div>
      </div>
      <button class="btn-primary" id="btn-create">+ Create Sheet</button>

      <div class="field">
        <label>Search by date</label>
        <div class="side-toggle">
          <input type="date" id="input-search" style="flex:1; min-width:140px; border:1px solid var(--line, #d8ddd8); border-radius:10px; padding:10px 12px; font-size:14px;">
          <button type="button" id="btn-clear-search" class="btn-secondary" style="flex:0 0 auto;">All</button>
        </div>
      </div>

      ${teams.length > 0 ? `
      <div class="field">
        <label>Filter by crew</label>
        <select id="input-regu-filter" style="width:100%; border:1px solid var(--line, #d8ddd8); border-radius:10px; padding:10px 12px; font-size:14px;">
          <option value="">All Crews</option>
          ${teams.map((t) => `<option value="${t.id}">${t.name}</option>`).join('')}
        </select>
      </div>
      ` : ''}

      <div class="section-label" id="draft-label">In Progress</div>
      <div id="draft-list"></div>

      <div class="section-label" id="history-label">History</div>
      <div id="history-list"></div>

      <div class="sync-note">Drafts never expire — you can continue anytime</div>
    </div>
  `;

  const draftContainer = root.querySelector('#draft-list');
  const historyContainer = root.querySelector('#history-list');
  const draftLabel = root.querySelector('#draft-label');
  const historyLabel = root.querySelector('#history-label');

  // Sisi belum diisi per lembar (buat subjudul kartu) dihitung sekali di
  // muka untuk semua lembar sebelum dirender -- getIncompleteSides itu async.
  const incompleteBySheetId = {};
  for (const s of sheets) {
    incompleteBySheetId[s.id] = await getIncompleteSides(s.id);
  }

  function sheetCardHtml(s) {
    const pillClass = s.status === 'draft' ? 'draft' : s.sync_status === 'synced' ? 'synced' : s.sync_status === 'conflict' ? 'draft' : 'pending';
    const pillLabel = s.status === 'draft' ? 'Draft' : s.sync_status === 'synced' ? 'Synced' : s.sync_status === 'conflict' ? 'Already on server (duplicate)' : 'Not synced';
    const shiftText = shiftCodeById[s.shift_id] ? shiftLabel(shiftCodeById[s.shift_id]) : '—';
    const crewText = teamCodeById[s.team_id] ? `Crew ${teamCodeById[s.team_id]}` : '—';
    const incomplete = incompleteBySheetId[s.id] ?? [];
    const progressText = incomplete.length === 0
      ? 'All sides filled in ✓'
      : `${incomplete.length} sides not filled in: ${incomplete.map((i) => i.label).join(', ')}`;
    return `
      <div class="sheet-card" data-id="${s.id}">
        <div>
          <div class="sheet-date">${formatDateDMY(s.tanggal)} • ${crewText} • ${shiftText}</div>
          <div class="sheet-shift">${progressText}</div>
        </div>
        <span class="pill ${pillClass}">${pillLabel}</span>
      </div>
    `;
  }

  // Cari tanggal + filter crew menyaring daftar draft & riwayat sekaligus
  // secara lokal -- data sudah ada semua di memori, tidak perlu query ulang.
  function renderLists(filterDate, filterTeamId) {
    let filtered = filterDate ? sheets.filter((s) => s.tanggal === filterDate) : sheets;
    if (filterTeamId) filtered = filtered.filter((s) => s.team_id === filterTeamId);
    const drafts = filtered.filter((s) => s.status === 'draft');
    const history = filtered.filter((s) => s.status !== 'draft');

    const suffix = filterDate ? ` (${formatDateDMY(filterDate)})` : '';
    draftLabel.textContent = `In Progress${suffix}`;
    historyLabel.textContent = `History${suffix}`;

    draftContainer.innerHTML = drafts.length
      ? drafts.map(sheetCardHtml).join('')
      : `<p class="empty-text">${filterDate || filterTeamId ? 'No drafts match this filter.' : 'No drafts yet.'}</p>`;
    historyContainer.innerHTML = history.length
      ? history.map(sheetCardHtml).join('')
      : `<p class="empty-text">${filterDate || filterTeamId ? 'No history matches this filter.' : 'No history yet.'}</p>`;
  }
  renderLists(null, null);

  const back = root.querySelector('#btn-back');
  const createBtn = root.querySelector('#btn-create');
  const shiftToggle = root.querySelector('#shift-toggle');

  const goBack = () => navigate('/temperature-menu');
  const tanggalInput = root.querySelector('#input-tanggal');

  const handleShiftPick = (e) => {
    const btn = e.target.closest('button[data-shift-id]');
    if (!btn || btn.disabled) return;
    selectedShiftId = btn.dataset.shiftId;
    shiftToggle.querySelectorAll('button').forEach((b) => b.classList.toggle('active', b === btn));
  };

  // Item #1: cek shift mana yang sudah "dipakai" regu lain di tanggal
  // terpilih, disable tombolnya + kasih tahu regu mana yang sudah pegang.
  const shiftHint = root.querySelector('#shift-availability-hint');
  const updateShiftAvailability = async () => {
    const taken = await getTakenShifts(moduleId, tanggalInput.value, user.team_id);
    const buttons = [...shiftToggle.querySelectorAll('button[data-shift-id]')];
    buttons.forEach((b) => { b.disabled = taken.has(b.dataset.shiftId); });

    if (selectedShiftId && taken.has(selectedShiftId)) {
      const fallback = buttons.find((b) => !taken.has(b.dataset.shiftId));
      selectedShiftId = fallback ? fallback.dataset.shiftId : null;
      buttons.forEach((b) => b.classList.toggle('active', b.dataset.shiftId === selectedShiftId));
    }

    const allTaken = buttons.length > 0 && buttons.every((b) => taken.has(b.dataset.shiftId));
    createBtn.disabled = allTaken;
    createBtn.style.opacity = allTaken ? '0.4' : '1';

    if (allTaken) {
      shiftHint.textContent = 'Both shifts already have a crew rostered for this date.';
    } else if (taken.size > 0) {
      shiftHint.textContent = [...taken.entries()]
        .map(([shiftId, teamName]) => `${shiftLabel(shiftCodeById[shiftId])} already used by ${teamName}`)
        .join(' · ');
    } else {
      shiftHint.textContent = '';
    }
  };

  const handleCreate = async () => {
    const tanggal = tanggalInput.value;
    if (!tanggal) {
      alert('Pick a sheet date first.');
      return;
    }
    if (!selectedShiftId) {
      alert('Pick a shift first.');
      return;
    }
    try {
      // Tarik ulang sekali lagi tepat sebelum bikin lembar -- memperkecil
      // celah race kalau layar ini sudah lama terbuka sebelum tombol ditekan
      // (lihat catatan lib/pull-sync.js soal kenapa ini penting).
      try {
        if (requireRole('admin', 'supervisor', 'foreman')) {
          await pullTeamDrafts(null);
        } else if (user.team_id) {
          await pullTeamDrafts(user.team_id);
        }
      } catch { /* tetap lanjut walau gagal tarik */ }
      const shiftCode = shiftCodeById[selectedShiftId];
      const [teamId, resolvedModuleId] = await Promise.all([
        resolveTeam(user, shiftCode),
        moduleId ? Promise.resolve(moduleId) : resolveModuleId(),
      ]);

      // Jaring pengaman terakhir (Item #1): cek ulang tepat sebelum insert,
      // pakai teamId yang SUDAH di-resolve (bukan cuma user.team_id mentah --
      // penting utk admin/supervisor yang team-nya ditebak dari roster) --
      // kalau ternyata baru saja dipakai regu lain (race condition), batalkan.
      const takenNow = await getTakenShifts(resolvedModuleId, tanggal, teamId);
      if (takenNow.has(selectedShiftId)) {
        alert(`This shift was just taken by ${takenNow.get(selectedShiftId)} for this date. Pick the other shift.`);
        await updateShiftAvailability();
        return;
      }

      const sheetId = await createSheet({
        moduleId: resolvedModuleId,
        templateVersion: TEMPLATE_VERSION,
        tanggal,
        shiftId: selectedShiftId,
        teamId,
        createdBy: user.id,
      });
      navigate(`/breaker-equipment?sheetId=${sheetId}&round=1`);
    } catch (err) {
      alert(`Failed to create sheet: ${err.message}`);
    }
  };

  const handleRootClick = (e) => {
    const card = e.target.closest('.sheet-card');
    if (!card) return;
    navigate(`/breaker-equipment?sheetId=${card.dataset.id}&round=1`);
  };

  const searchInput = root.querySelector('#input-search');
  const clearSearchBtn = root.querySelector('#btn-clear-search');
  const teamFilterSelect = root.querySelector('#input-regu-filter');
  const handleSearch = () => renderLists(searchInput.value || null, teamFilterSelect?.value || null);
  const handleClearSearch = () => {
    searchInput.value = '';
    renderLists(null, teamFilterSelect?.value || null);
  };
  const handleTeamFilter = () => renderLists(searchInput.value || null, teamFilterSelect.value || null);

  back.addEventListener('click', goBack);
  createBtn.addEventListener('click', handleCreate);
  shiftToggle.addEventListener('click', handleShiftPick);
  root.addEventListener('click', handleRootClick);
  searchInput.addEventListener('change', handleSearch);
  clearSearchBtn.addEventListener('click', handleClearSearch);
  teamFilterSelect?.addEventListener('change', handleTeamFilter);
  tanggalInput.addEventListener('change', updateShiftAvailability);
  updateShiftAvailability();

  return () => {
    back.removeEventListener('click', goBack);
    createBtn.removeEventListener('click', handleCreate);
    shiftToggle.removeEventListener('click', handleShiftPick);
    root.removeEventListener('click', handleRootClick);
    searchInput.removeEventListener('change', handleSearch);
    clearSearchBtn.removeEventListener('click', handleClearSearch);
    teamFilterSelect?.removeEventListener('change', handleTeamFilter);
    tanggalInput.removeEventListener('change', updateShiftAvailability);
  };
}
