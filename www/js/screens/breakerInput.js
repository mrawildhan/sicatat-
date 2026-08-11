import { getOrCreateRound, getUnitStatus, setUnitStatus, saveReading, getReadingsForUnit } from '../lib/db.js';
import { getCurrentUser } from '../lib/auth.js';
import { navigate } from '../lib/router.js';
import { supabase } from '../lib/supabase-client.js';

// Titik ukur gearbox — sama untuk breaker & sizer (Input Shaft = titik 4, dikonfirmasi berlaku keduanya)
const POINT_CODES = [
  { code: 'gb_low_speed', label: 'Low speed' },
  { code: 'gb_intermediate', label: 'Intermediate' },
  { code: 'gb_high_speed', label: 'High speed' },
  { code: 'gb_input_shaft', label: 'Input shaft' },
];

const STATUS_OPTIONS = [
  { value: 'beroperasi', label: 'Beroperasi' },
  { value: 'tidak_beroperasi', label: 'Tidak beroperasi' },
  { value: 'tidak_dapat_diakses', label: 'Tidak dapat diakses' },
];

const SECTION_LABELS = {
  gearbox_breaker: 'Temperature Gearbox Breaker',
  gearbox_sizer: 'Temperature Gearbox Sizer',
};

// SEMENTARA: tetap 2 ronde per section (breaker & sizer masing-masing),
// dikonfirmasi manual — belum dibaca dari form_template.
const TOTAL_ROUNDS = 2;

// PENTING: sebelumnya kode di sini memakai `code` teks (mis. "gb_low_speed")
// LANGSUNG sebagai measurement_point_id — itu salah, dan baru ketahuan saat
// sinkron ke server ("invalid input syntax for type uuid"). SQLite lokal
// tidak menegakkan tipe UUID jadi bug ini tidak kelihatan sebelum sinkron
// dicoba. Sekarang UUID asli diambil dulu dari Supabase.
async function resolvePoints() {
  const { data, error } = await supabase
    .from('measurement_point')
    .select('id, code')
    .is('equipment_id', null); // titik gearbox itu sendiri, bukan milik equipment tertentu
  if (error) throw new Error(`Gagal ambil titik ukur: ${error.message}`);

  return POINT_CODES.map((p) => {
    const found = data.find((d) => d.code === p.code);
    if (!found) throw new Error(`Titik ukur "${p.code}" belum ada di master data measurement_point`);
    return { ...p, id: found.id };
  });
}

export async function renderBreakerInput(root, params) {
  const sheetId = params.get('sheetId');
  const roundNumber = Number(params.get('round') || 1);
  const section = params.get('section') || 'gearbox_breaker';
  let currentSide = params.get('side') || 'BARAT';

  const roundId = await getOrCreateRound(sheetId, section, roundNumber);
  const user = getCurrentUser();
  const POINTS = await resolvePoints();

  // Ronde belum habis -> ronde berikutnya di section yang sama. Ronde habis
  // & masih di breaker -> lanjut ke Gearbox Sizer (round 1). Ronde habis &
  // sudah di sizer -> Layar Nama Crew (wireframe 4c), baru dari situ ke
  // Ringkasan.
  function nextStep() {
    if (roundNumber < TOTAL_ROUNDS) {
      return {
        label: `Lanjut → Ronde ${roundNumber + 1}`,
        path: `/breaker-equipment?sheetId=${sheetId}&round=${roundNumber + 1}&section=${section}`,
      };
    }
    if (section === 'gearbox_breaker') {
      return {
        label: 'Lanjut → Gearbox Sizer',
        path: `/breaker-equipment?sheetId=${sheetId}&round=1&section=gearbox_sizer`,
      };
    }
    return { label: 'Lanjut → Nama Crew', path: `/crew-names?sheetId=${sheetId}` };
  }

  async function draw() {
    const unitStatus = await getUnitStatus(roundId, currentSide, null);
    const status = unitStatus?.status ?? null; // null = "Belum diisi" (FR-26a) — bukan pilihan keempat
    const savedReadings = status === 'beroperasi'
      ? await getReadingsForUnit(roundId, unitStatus?.id ?? null)
      : {};

    root.innerHTML = `
      <div class="topbar">
        <button class="btn-back" id="btn-back">← Equipment</button>
        <div class="topbar-label">Lanjutan · Ronde ${roundNumber}</div>
        <div class="topbar-title">${SECTION_LABELS[section]}</div>
      </div>
      <div class="screen-body">
        <div class="side-toggle">
          <button data-side="BARAT" class="${currentSide === 'BARAT' ? 'active' : ''}">BARAT</button>
          <button data-side="TIMUR" class="${currentSide === 'TIMUR' ? 'active' : ''}">TIMUR</button>
        </div>

        <div class="status-select">
          <div class="status-select-label">Status unit sisi ini</div>
          <div class="status-options">
            ${STATUS_OPTIONS.map(
              (opt) => `
              <label class="status-opt">
                <input type="radio" name="status" value="${opt.value}" ${status === opt.value ? 'checked' : ''}>
                ${opt.label}
              </label>
            `
            ).join('')}
          </div>
        </div>

        ${
          status === null
            ? `<div class="warn-box">Belum ada yang dipilih. Ini bukan status apa pun — murni belum dijawab. Lembar tidak bisa dikirim selama ini kosong.</div>`
            : status !== 'beroperasi'
            ? `
              <div class="field">
                <label>Alasan (wajib)</label>
                <input id="reason" type="text" value="${unitStatus?.reason ?? ''}" placeholder="Jelaskan alasannya">
              </div>
              <div class="warn-box">Karena status bukan "Beroperasi", titik ukur 1–4 disembunyikan dan tidak wajib diisi.</div>
            `
            : `
              <div class="point-fields" id="point-fields">
                ${POINTS.map(
                  (p) => `
                  <div class="field">
                    <label>${p.label} °C</label>
                    <input type="number" step="0.1" data-point="${p.id}"
                      value="${savedReadings[p.id]?.value_numeric ?? ''}" placeholder="—">
                  </div>
                `
                ).join('')}
              </div>
            `
        }

        <button class="btn-primary" id="btn-selesai" style="margin-top:20px;">
          ${nextStep().label}
        </button>
      </div>
    `;

    await wireEvents(unitStatus);
  }

  async function wireEvents(unitStatus) {
    const back = root.querySelector('#btn-back');
    back.addEventListener('click', () => navigate(`/breaker-equipment?sheetId=${sheetId}&round=${roundNumber}&section=${section}`));

    const selesaiBtn = root.querySelector('#btn-selesai');
    selesaiBtn.addEventListener('click', () => navigate(nextStep().path));

    root.querySelectorAll('.side-toggle button').forEach((btn) => {
      btn.addEventListener('click', () => {
        currentSide = btn.dataset.side;
        draw();
      });
    });

    root.querySelectorAll('input[name="status"]').forEach((radio) => {
      radio.addEventListener('change', async () => {
        const reasonInput = root.querySelector('#reason');
        await setUnitStatus({
          roundId,
          unitCode: currentSide,
          equipmentId: null,
          status: radio.value,
          reason: reasonInput?.value ?? null,
        });
        draw(); // gambar ulang supaya field titik ukur muncul/hilang sesuai status baru
      });
    });

    const reasonInput = root.querySelector('#reason');
    if (reasonInput) {
      reasonInput.addEventListener('blur', async () => {
        await setUnitStatus({
          roundId,
          unitCode: currentSide,
          equipmentId: null,
          status: unitStatus.status,
          reason: reasonInput.value,
        });
      });
    }

    root.querySelectorAll('#point-fields input').forEach((input) => {
      input.addEventListener('blur', async () => {
        if (input.value === '') return;
        await saveReading({
          roundId,
          unitStatusId: unitStatus?.id ?? null,
          measurementPointId: input.dataset.point,
          valueNumeric: Number(input.value),
          recordedBy: user.id,
        });
      });
    });
  }

  await draw();
  return () => {}; // cleanup listener kompleks di sini masih TODO — lihat catatan README soal utang teknis MVP
}