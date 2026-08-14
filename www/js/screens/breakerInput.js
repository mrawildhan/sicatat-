import { getOrCreateRound, getRound, setRoundJam, getUnitStatus, setUnitStatus, saveReading, getReadingsForUnit, saveContributors, getContributors } from '../lib/db.js';
import { getCurrentUser } from '../lib/auth.js';
import { navigate } from '../lib/router.js';
import { supabase } from '../lib/supabase-client.js';
import { tempFieldClass } from '../lib/tempColor.js';

function nowHHMM() {
  const d = new Date();
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

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

  // Jam ronde ini (berlaku untuk BARAT & TIMUR sekaligus — satu ronde, satu
  // waktu keliling). Kalau belum pernah diisi, default ke jam saat ini &
  // langsung disimpan (supaya tidak pernah kosong "seperti kertas kosong"),
  // tapi tetap bisa dikoreksi manual kalau waktu cek sebenarnya beda.
  let round = await getRound(roundId);
  if (!round.jam) {
    round.jam = nowHHMM();
    await setRoundJam(roundId, round.jam);
  }

  // Satu Ronde = satu putaran keliling yang mencakup breaker DAN sizer (bukan
  // habiskan semua ronde breaker dulu baru pindah sizer). Jadi: Breaker
  // Ronde 1 -> Sizer Ronde 1 -> Breaker Ronde 2 -> Sizer Ronde 2 -> Ringkasan.
  // Nama Crew Pengisi tidak lagi layar terpisah -- otomatis diisi user yang
  // login begitu ronde terakhir selesai (dikonfirmasi user 2026-08-13).
  function nextStep() {
    if (section === 'gearbox_breaker') {
      return {
        label: 'Lanjut → Gearbox Sizer',
        path: `/breaker-equipment?sheetId=${sheetId}&round=${roundNumber}&section=gearbox_sizer`,
      };
    }
    if (roundNumber < TOTAL_ROUNDS) {
      return {
        label: `Lanjut → Ronde ${roundNumber + 1}`,
        path: `/breaker-equipment?sheetId=${sheetId}&round=${roundNumber + 1}&section=gearbox_breaker`,
      };
    }
    return { label: 'Simpan & Lanjut → Ringkasan', path: `/summary?sheetId=${sheetId}`, isFinal: true };
  }

  async function draw() {
    const unitStatus = await getUnitStatus(roundId, currentSide, null);
    const status = unitStatus?.status ?? null; // null = "Belum diisi" (FR-26a) — bukan pilihan keempat
    const savedReadings = status === 'beroperasi'
      ? await getReadingsForUnit(roundId, unitStatus?.id ?? null)
      : {};

    root.innerHTML = `
      <div class="topbar">
        <button class="btn-back" id="btn-back">← Ringkasan</button>
        <div class="topbar-label">Lanjutan · Ronde ${roundNumber}</div>
        <div class="topbar-title">${SECTION_LABELS[section]}</div>
      </div>
      <div class="screen-body">
        <div class="field">
          <label>Jam Ronde ${roundNumber} (berlaku BARAT &amp; TIMUR)</label>
          <input type="time" id="input-jam" value="${round.jam}">
        </div>

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
                      value="${savedReadings[p.id]?.value_numeric ?? ''}"
                      class="${tempFieldClass(savedReadings[p.id]?.value_numeric)}" placeholder="—">
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
    // Selalu ke Ringkasan, bukan ke Equipment ronde ini -- lihat catatan
    // sama di equipmentInput.js (dikonfirmasi user 2026-08-13).
    back.addEventListener('click', () => navigate(`/summary?sheetId=${sheetId}`));

    const selesaiBtn = root.querySelector('#btn-selesai');
    selesaiBtn.addEventListener('click', async () => {
      const step = nextStep();
      // Dicatat di TIAP ronde yang diselesaikan, bukan cuma ronde final --
      // supaya kalau orang berbeda (tapi regu sama) isi ronde berbeda-beda
      // dari HP masing-masing, semua orang yang ikut isi tercatat sebagai
      // kontributor, bukan cuma siapa yang kebetulan menutup ronde terakhir.
      // Idempoten per user.id -- aman diklik berkali-kali / bolak-balik layar.
      const already = await getContributors(sheetId);
      if (!already.includes(user.id)) {
        await saveContributors(sheetId, [user.id]);
      }
      navigate(step.path);
    });

    const jamInput = root.querySelector('#input-jam');
    jamInput.addEventListener('change', async () => {
      if (!jamInput.value) return;
      round.jam = jamInput.value;
      await setRoundJam(roundId, jamInput.value);
    });

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
        input.className = tempFieldClass(input.value);
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