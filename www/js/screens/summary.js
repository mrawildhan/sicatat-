import { getSheet, getUnitStatus, submitSheet, forceSubmitSheet, getContributors, initDb } from '../lib/db.js';
import { getCurrentUser, requireRole } from '../lib/auth.js';
import { navigate } from '../lib/router.js';

// SEMENTARA: Gearbox Breaker + Sizer, Ronde 1 & 2 tetap. Idealnya dibaca dari
// struktur form_template, bukan di-hardcode seperti sekarang.
const EXPECTED_SIDES = [
  { section: 'gearbox_breaker', roundNumber: 1, unitCode: 'BARAT', label: 'Gb. Breaker — Ronde 1 · BARAT' },
  { section: 'gearbox_breaker', roundNumber: 1, unitCode: 'TIMUR', label: 'Gb. Breaker — Ronde 1 · TIMUR' },
  { section: 'gearbox_breaker', roundNumber: 2, unitCode: 'BARAT', label: 'Gb. Breaker — Ronde 2 · BARAT' },
  { section: 'gearbox_breaker', roundNumber: 2, unitCode: 'TIMUR', label: 'Gb. Breaker — Ronde 2 · TIMUR' },
  { section: 'gearbox_sizer', roundNumber: 1, unitCode: 'BARAT', label: 'Gb. Sizer — Ronde 1 · BARAT' },
  { section: 'gearbox_sizer', roundNumber: 1, unitCode: 'TIMUR', label: 'Gb. Sizer — Ronde 1 · TIMUR' },
  { section: 'gearbox_sizer', roundNumber: 2, unitCode: 'BARAT', label: 'Gb. Sizer — Ronde 2 · BARAT' },
  { section: 'gearbox_sizer', roundNumber: 2, unitCode: 'TIMUR', label: 'Gb. Sizer — Ronde 2 · TIMUR' },
];

export async function renderSummary(root, params) {
  const sheetId = params.get('sheetId');
  const user = getCurrentUser();

  root.innerHTML = `<div class="screen-body"><p class="empty-text">Memuat...</p></div>`;

  const sheet = await getSheet(sheetId);
  if (!sheet) {
    root.innerHTML = `<div class="screen-body"><div class="warn-box">Lembar tidak ditemukan.</div></div>`;
    return () => {};
  }

  // Untuk tiap sisi yang diharapkan, cek statusnya. Perlu roundId per section
  // — kita cari lewat query sederhana karena getOrCreateRound akan MEMBUAT
  // ronde baru kalau belum ada (tidak cocok dipakai di layar ringkasan yang
  // sifatnya cuma membaca, bukan menulis) — jadi di sini pakai query manual.
  const rows = [];
  for (const expected of EXPECTED_SIDES) {
    const roundId = await findRoundId(sheetId, expected.section, expected.roundNumber);
    const status = roundId ? (await getUnitStatus(roundId, expected.unitCode, null))?.status ?? null : null;
    rows.push({ ...expected, status });
  }

  const belumDiisi = rows.filter((r) => r.status === null);
  const contributors = await getContributors(sheetId);
  const crewBelumDiisi = contributors.length === 0;
  const bisaSubmit = belumDiisi.length === 0 && !crewBelumDiisi;

  // FR-15: jalur override -- Foreman/Supervisor/Admin boleh kirim lembar
  // meski ada sisi ronde belum diisi (mis. shift habis, crew harus pulang).
  // Nama Crew Pengisi TETAP wajib -- override cuma untuk data ukur yang
  // belum lengkap, bukan alasan buat tidak mencatat siapa yang mengisi.
  const canOverride = belumDiisi.length > 0 && !crewBelumDiisi && requireRole('foreman', 'supervisor', 'admin');

  root.innerHTML = `
    <div class="topbar">
      <button class="btn-back" id="btn-back">← Daftar Lembar</button>
      <div class="topbar-title">Ringkasan Lembar</div>
    </div>
    <div class="screen-body">
      <div class="section-label">${sheet.tanggal}</div>

      ${rows
        .map(
          (r) => `
        <div class="summary-row">
          <span class="summary-name">${r.label}</span>
          <span class="status-text ${r.status === null ? 'incomplete' : 'complete'}">
            ${r.status === null ? 'Belum diisi' : statusLabel(r.status)}
          </span>
        </div>
      `
        )
        .join('')}

      <div class="summary-row">
        <span class="summary-name">Nama Crew Pengisi</span>
        <span class="status-text ${crewBelumDiisi ? 'incomplete' : 'complete'}">
          ${crewBelumDiisi ? 'Belum diisi' : `${contributors.length} orang ✓`}
        </span>
      </div>

      ${
        belumDiisi.length > 0
          ? `<div class="warn-box">${belumDiisi.length} sisi masih "Belum diisi": ${belumDiisi.map((r) => r.label).join(', ')}. Lembar tidak dapat dikirim sampai semua terjawab.</div>`
          : ''
      }
      ${crewBelumDiisi ? `<div class="warn-box">Nama Crew Pengisi belum diisi.</div>` : ''}

      <button class="btn-primary" id="btn-submit" ${bisaSubmit ? '' : 'disabled style="opacity:0.4;"'}>
        Kirim Lembar
      </button>

      ${
        canOverride
          ? `
            <div class="status-select" style="margin-top:20px;">
              <div class="status-select-label">Jalur Override (${user.role}) — kirim meski belum lengkap</div>
              <div class="field">
                <label>Alasan (wajib)</label>
                <input id="force-reason" type="text" placeholder="Contoh: shift habis, crew sudah pulang">
              </div>
              <button class="btn-primary" id="btn-force-submit" style="margin-top:10px; opacity:0.4;" disabled>
                Kirim Sebagai "Tidak Lengkap"
              </button>
            </div>
          `
          : ''
      }
    </div>
  `;

  function statusLabel(status) {
    if (status === 'beroperasi') return 'Beroperasi ✓';
    if (status === 'tidak_beroperasi') return 'Tidak beroperasi';
    if (status === 'tidak_dapat_diakses') return 'Tidak dapat diakses';
    return status;
  }

  const back = root.querySelector('#btn-back');
  const goBack = () => navigate('/sheet-list');
  back.addEventListener('click', goBack);

  const submitBtn = root.querySelector('#btn-submit');
  const handleSubmit = async () => {
    if (!bisaSubmit) return;
    await submitSheet(sheetId);
    alert('Lembar berhasil dikirim. Akan tersinkron otomatis begitu online.');
    navigate('/sheet-list');
  };
  submitBtn.addEventListener('click', handleSubmit);

  let cleanupOverride = () => {};
  if (canOverride) {
    const reasonInput = root.querySelector('#force-reason');
    const forceBtn = root.querySelector('#btn-force-submit');
    const updateForceBtn = () => {
      const filled = reasonInput.value.trim().length > 0;
      forceBtn.disabled = !filled;
      forceBtn.style.opacity = filled ? '1' : '0.4';
    };
    const handleForceSubmit = async () => {
      const reason = reasonInput.value.trim();
      if (!reason) return;
      await forceSubmitSheet(sheetId, reason, user.id);
      alert('Lembar dikirim sebagai "Tidak Lengkap". Akan tersinkron otomatis begitu online.');
      navigate('/sheet-list');
    };
    reasonInput.addEventListener('input', updateForceBtn);
    forceBtn.addEventListener('click', handleForceSubmit);
    cleanupOverride = () => {
      reasonInput.removeEventListener('input', updateForceBtn);
      forceBtn.removeEventListener('click', handleForceSubmit);
    };
  }

  return () => {
    back.removeEventListener('click', goBack);
    submitBtn.removeEventListener('click', handleSubmit);
    cleanupOverride();
  };
}

async function findRoundId(sheetId, section, roundNumber) {
  const database = await initDb();
  const res = await database.query(
    'select id from round where sheet_id = ? and section = ? and round_number = ?',
    [sheetId, section, roundNumber]
  );
  return res.values?.[0]?.id ?? null;
}