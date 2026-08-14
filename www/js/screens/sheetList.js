import { listSheets, createSheet, getIncompleteSides } from '../lib/db.js';
import { getCurrentUser } from '../lib/auth.js';
import { navigate } from '../lib/router.js';
import { supabase } from '../lib/supabase-client.js';
import { computeTeamCodeForShift } from '../lib/roster.js';
import { pullTeamDrafts } from '../lib/pull-sync.js';

const TEMPLATE_VERSION = 'v0.4';

const SHIFT_LABELS = { PAGI: 'Siang (Day)', MALAM: 'Malam (Night)' };
function shiftLabel(code) {
  return SHIFT_LABELS[code] ?? code;
}

async function resolveModuleId() {
  const { data, error } = await supabase
    .from('module').select('id').eq('code', 'temperature_check').single();
  if (error) throw new Error(`Gagal ambil module: ${error.message}`);
  return data.id;
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
    if (teamError) throw new Error(`Gagal ambil tim: ${teamError.message}`);
    teamId = team.id;
  }

  return teamId;
}

export async function renderSheetList(root) {
  const user = getCurrentUser();

  // Tarik draft regu sendiri dari server dulu (kalau ada, & kalau online) --
  // supaya lembar yang mulai diisi dari HP orang lain (regu sama) muncul di
  // sini juga, bukan bikin duplikat. Cuma relevan utk crew/foreman (punya
  // team_id sendiri); supervisor/admin dilewati, lihat lib/pull-sync.js.
  if (user.team_id) {
    try {
      await pullTeamDrafts(user.team_id);
    } catch (err) {
      console.warn('sheetList: gagal tarik draft regu', err.message);
    }
  }

  const sheets = await listSheets();

  // Daftar shift buat picker Siang/Malam & buat label kartu riwayat. Kalau
  // offline saat cuma MELIHAT daftar (bukan bikin baru), gagal diam-diam --
  // kartu tetap tampil, cuma tanpa label shift.
  let shifts = [];
  try {
    const { data, error } = await supabase.from('shift').select('id, code').order('code');
    if (error) throw error;
    shifts = data ?? [];
  } catch {
    shifts = [];
  }
  const shiftCodeById = Object.fromEntries(shifts.map((s) => [s.id, s.code]));

  // Daftar regu buat filter -- sama seperti shift, gagal diam-diam kalau offline
  // (filter regu cuma tidak muncul, bukan mengganggu daftar lembar yang tetap tampil).
  let teams = [];
  try {
    const { data, error } = await supabase.from('team').select('id, name').order('code');
    if (error) throw error;
    teams = data ?? [];
  } catch {
    teams = [];
  }

  const currentHourCode = new Date().getHours() >= 7 && new Date().getHours() < 19 ? 'PAGI' : 'MALAM';
  let selectedShiftId = shifts.find((s) => s.code === currentHourCode)?.id ?? shifts[0]?.id ?? null;

  root.innerHTML = `
    <div class="topbar">
      <button class="btn-back" id="btn-back">← Temperature</div>
      <div class="topbar-title">Daily Temperature Check</div>
    </div>
    <div class="screen-body">
      <div class="field">
        <label>Tanggal lembar</label>
        <input type="date" id="input-tanggal" value="${new Date().toISOString().slice(0, 10)}">
      </div>
      <div class="field">
        <label>Shift</label>
        <div class="side-toggle" id="shift-toggle">
          ${shifts
            .map((s) => `<button type="button" data-shift-id="${s.id}" class="${s.id === selectedShiftId ? 'active' : ''}">${shiftLabel(s.code)}</button>`)
            .join('')}
        </div>
      </div>
      <button class="btn-primary" id="btn-create">+ Buat Lembar</button>
      <div class="hint-text">Default hari ini &amp; shift sesuai jam sekarang — ganti kalau mengisi susulan. Regu terisi otomatis dari jadwal roster — bisa dikoreksi jika meleset</div>

      <div class="field">
        <label>Cari tanggal</label>
        <div class="side-toggle">
          <input type="date" id="input-search" style="flex:1; min-width:140px; border:1px solid var(--line, #d8ddd8); border-radius:10px; padding:10px 12px; font-size:14px;">
          <button type="button" id="btn-clear-search" class="btn-secondary" style="flex:0 0 auto;">Semua</button>
        </div>
      </div>

      ${teams.length > 0 ? `
      <div class="field">
        <label>Filter regu</label>
        <select id="input-regu-filter" style="width:100%; border:1px solid var(--line, #d8ddd8); border-radius:10px; padding:10px 12px; font-size:14px;">
          <option value="">Semua Regu</option>
          ${teams.map((t) => `<option value="${t.id}">${t.name}</option>`).join('')}
        </select>
      </div>
      ` : ''}

      <div class="section-label" id="draft-label">Belum Selesai</div>
      <div id="draft-list"></div>

      <div class="section-label" id="history-label">Riwayat</div>
      <div id="history-list"></div>

      <div class="sync-note">Draft tidak kedaluwarsa — bisa dilanjutkan kapan saja</div>
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
    const pillLabel = s.status === 'draft' ? 'Draft' : s.sync_status === 'synced' ? 'Tersinkron' : s.sync_status === 'conflict' ? 'Sudah ada di server (duplikat)' : 'Belum tersinkron';
    const shiftText = shiftCodeById[s.shift_id] ? shiftLabel(shiftCodeById[s.shift_id]) : '—';
    const incomplete = incompleteBySheetId[s.id] ?? [];
    const progressText = incomplete.length === 0
      ? 'Semua sisi terisi ✓'
      : `${incomplete.length} sisi belum diisi: ${incomplete.map((i) => i.label).join(', ')}`;
    return `
      <div class="sheet-card" data-id="${s.id}">
        <div>
          <div class="sheet-date">${s.tanggal} · ${shiftText}</div>
          <div class="sheet-shift">${progressText}</div>
        </div>
        <span class="pill ${pillClass}">${pillLabel}</span>
      </div>
    `;
  }

  // Cari tanggal (mis. "3 Agustus") + filter regu menyaring daftar draft & riwayat
  // sekaligus secara lokal -- data sudah ada semua di memori, tidak perlu query ulang.
  function renderLists(filterDate, filterTeamId) {
    let filtered = filterDate ? sheets.filter((s) => s.tanggal === filterDate) : sheets;
    if (filterTeamId) filtered = filtered.filter((s) => s.team_id === filterTeamId);
    const drafts = filtered.filter((s) => s.status === 'draft');
    const history = filtered.filter((s) => s.status !== 'draft');

    const suffix = filterDate ? ` (tanggal ${filterDate})` : '';
    draftLabel.textContent = `Belum Selesai${suffix}`;
    historyLabel.textContent = `Riwayat${suffix}`;

    draftContainer.innerHTML = drafts.length
      ? drafts.map(sheetCardHtml).join('')
      : `<p class="empty-text">${filterDate || filterTeamId ? 'Tidak ada draft yang cocok filter.' : 'Belum ada draft.'}</p>`;
    historyContainer.innerHTML = history.length
      ? history.map(sheetCardHtml).join('')
      : `<p class="empty-text">${filterDate || filterTeamId ? 'Tidak ada riwayat yang cocok filter.' : 'Belum ada riwayat.'}</p>`;
  }
  renderLists(null, null);

  const back = root.querySelector('#btn-back');
  const createBtn = root.querySelector('#btn-create');
  const shiftToggle = root.querySelector('#shift-toggle');

  const goBack = () => navigate('/temperature-menu');
  const tanggalInput = root.querySelector('#input-tanggal');

  const handleShiftPick = (e) => {
    const btn = e.target.closest('button[data-shift-id]');
    if (!btn) return;
    selectedShiftId = btn.dataset.shiftId;
    shiftToggle.querySelectorAll('button').forEach((b) => b.classList.toggle('active', b === btn));
  };

  const handleCreate = async () => {
    const tanggal = tanggalInput.value;
    if (!tanggal) {
      alert('Pilih tanggal lembar dulu.');
      return;
    }
    if (!selectedShiftId) {
      alert('Pilih shift dulu.');
      return;
    }
    try {
      // Tarik ulang sekali lagi tepat sebelum bikin lembar -- memperkecil
      // celah race kalau layar ini sudah lama terbuka sebelum tombol ditekan
      // (lihat catatan lib/pull-sync.js soal kenapa ini penting).
      if (user.team_id) {
        try { await pullTeamDrafts(user.team_id); } catch { /* tetap lanjut walau gagal tarik */ }
      }
      const shiftCode = shiftCodeById[selectedShiftId];
      const [teamId, moduleId] = await Promise.all([
        resolveTeam(user, shiftCode),
        resolveModuleId(),
      ]);
      const sheetId = await createSheet({
        moduleId,
        templateVersion: TEMPLATE_VERSION,
        tanggal,
        shiftId: selectedShiftId,
        teamId,
        createdBy: user.id,
      });
      navigate(`/breaker-equipment?sheetId=${sheetId}&round=1`);
    } catch (err) {
      alert(`Gagal membuat lembar: ${err.message}`);
    }
  };

  const openSheet = (e) => {
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
  root.addEventListener('click', openSheet);
  searchInput.addEventListener('change', handleSearch);
  clearSearchBtn.addEventListener('click', handleClearSearch);
  teamFilterSelect?.addEventListener('change', handleTeamFilter);

  return () => {
    back.removeEventListener('click', goBack);
    createBtn.removeEventListener('click', handleCreate);
    shiftToggle.removeEventListener('click', handleShiftPick);
    root.removeEventListener('click', openSheet);
    searchInput.removeEventListener('change', handleSearch);
    clearSearchBtn.removeEventListener('click', handleClearSearch);
    teamFilterSelect?.removeEventListener('change', handleTeamFilter);
  };
}
