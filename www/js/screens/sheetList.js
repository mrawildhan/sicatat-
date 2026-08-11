import { listSheets, createSheet } from '../lib/db.js';
import { getCurrentUser } from '../lib/auth.js';
import { navigate } from '../lib/router.js';
import { supabase } from '../lib/supabase-client.js';
import { computeTeamCodeForShift } from '../lib/roster.js';

const TEMPLATE_VERSION = 'v0.4';

async function resolveModuleId() {
  const { data, error } = await supabase
    .from('module').select('id').eq('code', 'temperature_check').single();
  if (error) throw new Error(`Gagal ambil module: ${error.message}`);
  return data.id;
}

// FR-73: shift ditentukan dari jam saat ini (bukan bagian roster — roster
// cuma menentukan REGU mana yang piket, bukan jenis shift-nya). Regu
// dihitung otomatis dari roster_anchor (lihat lib/roster.js). Kalau
// roster_anchor belum dikonfigurasi admin, atau user bukan crew/foreman
// (mis. admin/supervisor bikin lembar tes) -- fallback ke team_id user
// sendiri atau tim pertama yang ada, supaya alur tidak nabrak foreign key
// constraint sementara roster belum diisi.
async function resolveShiftAndTeam(user) {
  const hour = new Date().getHours();
  const shiftCode = hour >= 7 && hour < 19 ? 'PAGI' : 'MALAM';

  const { data: shift, error: shiftError } = await supabase
    .from('shift').select('id').eq('code', shiftCode).single();
  if (shiftError) throw new Error(`Gagal ambil shift: ${shiftError.message}`);

  let teamId = null;
  let suggestedByRoster = false;

  const { data: anchor } = await supabase
    .from('roster_anchor').select('*').eq('is_active', true)
    .order('tanggal_mula', { ascending: false }).limit(1).maybeSingle();

  if (anchor) {
    const today = new Date().toISOString().slice(0, 10);
    const teamCode = computeTeamCodeForShift(anchor, today, shiftCode);
    if (teamCode) {
      const { data: team } = await supabase.from('team').select('id').eq('code', teamCode).single();
      if (team) { teamId = team.id; suggestedByRoster = true; }
    }
  }

  if (!teamId) teamId = user.team_id;
  if (!teamId) {
    const { data: team, error: teamError } = await supabase
      .from('team').select('id').order('code').limit(1).single();
    if (teamError) throw new Error(`Gagal ambil tim: ${teamError.message}`);
    teamId = team.id;
  }

  return { shiftId: shift.id, teamId, suggestedByRoster };
}

export async function renderSheetList(root) {
  const user = getCurrentUser();
  const sheets = await listSheets();

  root.innerHTML = `
    <div class="topbar">
      <button class="btn-back" id="btn-back">← Temperature</div>
      <div class="topbar-title">Daily Temperature Check</div>
    </div>
    <div class="screen-body">
      <button class="btn-primary" id="btn-create">+ Buat Lembar Hari Ini</button>
      <div class="hint-text">Shift &amp; regu terisi otomatis dari jadwal roster — bisa dikoreksi jika meleset</div>

      <div class="section-label">Belum Selesai</div>
      <div id="draft-list"></div>

      <div class="section-label">Riwayat</div>
      <div id="history-list"></div>

      <div class="sync-note">Draft tidak kedaluwarsa — bisa dilanjutkan kapan saja</div>
    </div>
  `;

  const draftContainer = root.querySelector('#draft-list');
  const historyContainer = root.querySelector('#history-list');

  const drafts = sheets.filter((s) => s.status === 'draft');
  const history = sheets.filter((s) => s.status !== 'draft');

  draftContainer.innerHTML = drafts.length
    ? drafts.map(sheetCardHtml).join('')
    : '<p class="empty-text">Belum ada draft.</p>';
  historyContainer.innerHTML = history.length
    ? history.map(sheetCardHtml).join('')
    : '<p class="empty-text">Belum ada riwayat.</p>';

  function sheetCardHtml(s) {
    const pillClass = s.status === 'draft' ? 'draft' : s.sync_status === 'synced' ? 'synced' : 'pending';
    const pillLabel = s.status === 'draft' ? 'Draft' : s.sync_status === 'synced' ? 'Tersinkron' : 'Belum tersinkron';
    return `
      <div class="sheet-card" data-id="${s.id}">
        <div>
          <div class="sheet-date">${s.tanggal}</div>
          <div class="sheet-shift">shift_id: ${s.shift_id}</div>
        </div>
        <span class="pill ${pillClass}">${pillLabel}</span>
      </div>
    `;
  }

  const back = root.querySelector('#btn-back');
  const createBtn = root.querySelector('#btn-create');

  const goBack = () => navigate('/temperature-menu');
  const handleCreate = async () => {
    try {
      const [{ shiftId, teamId }, moduleId] = await Promise.all([
        resolveShiftAndTeam(user),
        resolveModuleId(),
      ]);
      const today = new Date().toISOString().slice(0, 10);
      const sheetId = await createSheet({
        moduleId,
        templateVersion: TEMPLATE_VERSION,
        tanggal: today,
        shiftId,
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

  back.addEventListener('click', goBack);
  createBtn.addEventListener('click', handleCreate);
  root.addEventListener('click', openSheet);

  return () => {
    back.removeEventListener('click', goBack);
    createBtn.removeEventListener('click', handleCreate);
    root.removeEventListener('click', openSheet);
  };
}
