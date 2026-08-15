import { getSheet, getUnitStatus, submitSheet, forceSubmitSheet, getContributors, initDb, EXPECTED_SIDES } from '../lib/db.js';
import { getCurrentUser, requireRole } from '../lib/auth.js';
import { navigate } from '../lib/router.js';
import { buildExportRows, resolveContributorNames, resolveSheetContext, buildCsv, buildPdf, pdfToBase64, saveAndShareText, saveAndShareBase64 } from '../lib/export.js';
import { syncNow, deleteSheet } from '../lib/sync-engine.js';

export async function renderSummary(root, params) {
  const sheetId = params.get('sheetId');
  const user = getCurrentUser();

  root.innerHTML = `<div class="screen-body"><p class="empty-text">Loading...</p></div>`;

  const sheet = await getSheet(sheetId);
  if (!sheet) {
    root.innerHTML = `<div class="screen-body"><div class="warn-box">Sheet not found.</div></div>`;
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
      <button class="btn-back" id="btn-back">← Sheet List</button>
      <div class="topbar-title">Sheet Summary</div>
    </div>
    <div class="screen-body">
      <div class="section-label">${sheet.tanggal}</div>

      ${rows
        .map(
          (r) => `
        <div class="summary-row" ${r.status === null ? `data-fill="${r.section}|${r.roundNumber}|${r.unitCode}" style="cursor:pointer;"` : ''}>
          <span class="summary-name">${r.label}</span>
          <span class="status-text ${r.status === null ? 'incomplete' : 'complete'}">
            ${r.status === null ? 'Not filled in →' : statusLabel(r.status)}
          </span>
        </div>
      `
        )
        .join('')}

      <div class="summary-row">
        <span class="summary-name">Filled By</span>
        <span class="status-text ${crewBelumDiisi ? 'incomplete' : 'complete'}">
          ${crewBelumDiisi ? 'Not filled in' : `${contributors.length} people ✓`}
        </span>
      </div>

      ${
        belumDiisi.length > 0
          ? `<div class="warn-box">${belumDiisi.length} side(s) still "Not filled in": ${belumDiisi.map((r) => r.label).join(', ')}. The sheet cannot be submitted until all are answered.</div>`
          : ''
      }
      ${crewBelumDiisi ? `<div class="warn-box">Filled By has not been recorded yet.</div>` : ''}

      <button class="btn-primary" id="btn-submit" ${bisaSubmit ? '' : 'disabled style="opacity:0.4;"'}>
        Submit Sheet
      </button>

      ${
        canOverride
          ? `
            <div class="status-select" style="margin-top:20px;">
              <div class="status-select-label">Override (${user.role}) — submit even if incomplete</div>
              <div class="field">
                <label>Reason (required)</label>
                <input id="force-reason" type="text" placeholder="e.g. shift ended, crew already left">
              </div>
              <button class="btn-primary" id="btn-force-submit" style="margin-top:10px; opacity:0.4;" disabled>
                Submit As "Incomplete"
              </button>
            </div>
          `
          : ''
      }

      <div class="section-label">Export (FR-62/63)</div>
      <button class="btn-secondary" id="btn-export-csv" style="margin-bottom:10px;">Export Excel (CSV)</button>
      <button class="btn-secondary" id="btn-export-pdf">Export PDF</button>

      <button class="btn-danger" id="btn-delete-sheet">Delete Sheet</button>
    </div>
  `;

  function statusLabel(status) {
    if (status === 'beroperasi') return 'Operating ✓';
    if (status === 'tidak_beroperasi') return 'Not operating';
    if (status === 'tidak_dapat_diakses') return 'Not accessible';
    return status;
  }

  const back = root.querySelector('#btn-back');
  const goBack = () => navigate('/sheet-list');
  back.addEventListener('click', goBack);

  // Klik langsung baris "Belum diisi" -> loncat ke form ronde/sisi itu juga,
  // tidak perlu balik ke Daftar Lembar & klik ulang dari Ronde 1.
  const handleFillClick = (e) => {
    const row = e.target.closest('[data-fill]');
    if (!row) return;
    const [section, roundNumber, unitCode] = row.dataset.fill.split('|');
    navigate(`/breaker-input?sheetId=${sheetId}&round=${roundNumber}&section=${section}&side=${unitCode}`);
  };
  root.addEventListener('click', handleFillClick);

  const submitBtn = root.querySelector('#btn-submit');
  const handleSubmit = async () => {
    if (!bisaSubmit) return;
    await submitSheet(sheetId);
    syncNow(); // coba sinkron langsung kalau kebetulan online, jangan nunggu interval berkala
    alert(navigator.onLine
      ? 'Sheet submitted and syncing now.'
      : 'Sheet submitted. It will sync automatically once you\'re back online.');
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
      syncNow();
      alert(navigator.onLine
        ? 'Sheet submitted as "Incomplete" and syncing now.'
        : 'Sheet submitted as "Incomplete". It will sync automatically once you\'re back online.');
      navigate('/sheet-list');
    };
    reasonInput.addEventListener('input', updateForceBtn);
    forceBtn.addEventListener('click', handleForceSubmit);
    cleanupOverride = () => {
      reasonInput.removeEventListener('input', updateForceBtn);
      forceBtn.removeEventListener('click', handleForceSubmit);
    };
  }

  const exportCsvBtn = root.querySelector('#btn-export-csv');
  const exportPdfBtn = root.querySelector('#btn-export-pdf');
  const handleExportCsv = async () => {
    exportCsvBtn.textContent = 'Preparing...';
    try {
      const exportRows = await buildExportRows(sheetId);
      const [names, sheetContext] = await Promise.all([resolveContributorNames(contributors), resolveSheetContext(sheet)]);
      const csv = buildCsv(sheet, sheetContext, names, exportRows);
      await saveAndShareText(csv, `sicatat-${sheet.tanggal}.csv`);
    } catch (err) {
      alert(`Failed to export CSV: ${err.message}`);
    } finally {
      exportCsvBtn.textContent = 'Export Excel (CSV)';
    }
  };
  const handleExportPdf = async () => {
    exportPdfBtn.textContent = 'Preparing...';
    try {
      const exportRows = await buildExportRows(sheetId);
      const [names, sheetContext] = await Promise.all([resolveContributorNames(contributors), resolveSheetContext(sheet)]);
      const doc = buildPdf(sheet, sheetContext, names, exportRows);
      await saveAndShareBase64(pdfToBase64(doc), `sicatat-${sheet.tanggal}.pdf`);
    } catch (err) {
      alert(`Failed to export PDF: ${err.message}`);
    } finally {
      exportPdfBtn.textContent = 'Export PDF';
    }
  };
  exportCsvBtn.addEventListener('click', handleExportCsv);
  exportPdfBtn.addEventListener('click', handleExportPdf);

  const deleteBtn = root.querySelector('#btn-delete-sheet');
  const handleDelete = async () => {
    if (!confirm('Delete this sheet? This cannot be undone.')) return;
    deleteBtn.disabled = true;
    try {
      await deleteSheet(sheetId);
      navigate('/sheet-list');
    } catch (err) {
      alert(`Failed to delete: ${err.message}`);
      deleteBtn.disabled = false;
    }
  };
  deleteBtn.addEventListener('click', handleDelete);

  return () => {
    back.removeEventListener('click', goBack);
    root.removeEventListener('click', handleFillClick);
    submitBtn.removeEventListener('click', handleSubmit);
    cleanupOverride();
    exportCsvBtn.removeEventListener('click', handleExportCsv);
    exportPdfBtn.removeEventListener('click', handleExportPdf);
    deleteBtn.removeEventListener('click', handleDelete);
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