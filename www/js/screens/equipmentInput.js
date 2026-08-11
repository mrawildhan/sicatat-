import { getOrCreateRound, getReadingsForUnit, saveReading } from '../lib/db.js';
import { getCurrentUser } from '../lib/auth.js';
import { navigate } from '../lib/router.js';
import { supabase } from '../lib/supabase-client.js';

// Matriks field per equipment — sesuai PRD Bagian 5.2. Field yang TIDAK
// disebut di sini untuk suatu equipment TIDAK ditampilkan sama sekali
// (bukan ditampilkan kosong/disabled) — ini realisasi FR-21.
const EQUIPMENT_FIELDS = {
  feeder_breaker: ['motor_de', 'motor_nde', 'drum_east', 'drum_west', 'oil_level', 'gear_box', 'remark'],
  hydraulic_pump_1: ['motor_de', 'motor_nde', 'chain_head', 'chain_tail', 'oil_level', 'remark'],
  hydraulic_pump_2: ['motor_de', 'motor_nde', 'chain_head', 'chain_tail', 'oil_level', 'remark'],
  heat_exchanger: ['motor_de', 'motor_nde', 'oil_level', 'remark'],
};

const FIELD_LABELS = {
  motor_de: 'Motor DE °C',
  motor_nde: 'Motor NDE °C',
  drum_east: 'Drum East °C',
  drum_west: 'Drum West °C',
  chain_head: 'Chain Head °C',
  chain_tail: 'Chain Tail °C',
  gear_box: 'Gear box °C',
  remark: 'Remark',
};

async function fetchEquipmentWithPoints() {
  const { data: equipmentRows, error: eqError } = await supabase
    .from('equipment').select('id, code, name, sort_order').order('sort_order');
  if (eqError) throw new Error(`Gagal ambil equipment: ${eqError.message}`);

  const { data: pointRows, error: ptError } = await supabase
    .from('measurement_point').select('id, code, equipment_id, data_type');
  if (ptError) throw new Error(`Gagal ambil measurement_point: ${ptError.message}`);

  // Petakan point per equipment_id supaya gampang dicari layar per kartu.
  const pointsByEquipment = {};
  for (const p of pointRows) {
    if (!p.equipment_id) continue; // titik gearbox itu sendiri (equipment_id null), bukan urusan layar ini
    (pointsByEquipment[p.equipment_id] ??= []).push(p);
  }

  return { equipmentRows, pointsByEquipment };
}

export async function renderEquipmentInput(root, params) {
  const sheetId = params.get('sheetId');
  const roundNumber = Number(params.get('round') || 1);
  const user = getCurrentUser();

  root.innerHTML = `<div class="screen-body"><p class="empty-text">Memuat...</p></div>`;

  let roundId, equipmentRows, pointsByEquipment, savedReadings;
  try {
    roundId = await getOrCreateRound(sheetId, 'gearbox_breaker', roundNumber);
    ({ equipmentRows, pointsByEquipment } = await fetchEquipmentWithPoints());
    savedReadings = await getReadingsForUnit(roundId, null); // null = readings equipment, bukan sisi BARAT/TIMUR
  } catch (err) {
    root.innerHTML = `<div class="screen-body"><div class="warn-box">Gagal memuat: ${err.message}</div></div>`;
    return () => {};
  }

  function fieldValueHtml(point) {
    const saved = savedReadings[point.id];
    if (point.data_type === 'boolean') {
      const current = saved?.value_boolean;
      return `
        <div class="field">
          <label>Oil Level</label>
          <div class="oil-toggle" data-point-bool="${point.id}">
            <button type="button" data-bool="true" class="${current === true ? 'selected' : ''}">OK</button>
            <button type="button" data-bool="false" class="${current === false ? 'selected' : ''}">Low</button>
          </div>
        </div>
      `;
    }
    if (point.data_type === 'text') {
      return `
        <div class="field">
          <label>${FIELD_LABELS[point.code] ?? point.code}</label>
          <input type="text" data-point-text="${point.id}" value="${saved?.value_text ?? ''}" placeholder="Opsional">
        </div>
      `;
    }
    return `
      <div class="field">
        <label>${FIELD_LABELS[point.code] ?? point.code}</label>
        <input type="number" step="0.1" data-point-num="${point.id}" value="${saved?.value_numeric ?? ''}" placeholder="—">
      </div>
    `;
  }

  root.innerHTML = `
    <div class="topbar">
      <button class="btn-back" id="btn-back">← Daftar Lembar</div>
      <div class="topbar-label">Ronde ${roundNumber}</div>
      <div class="topbar-title">Gearbox Breaker</div>
    </div>
    <div class="screen-body">
      ${equipmentRows
        .map((eq) => {
          const allowedCodes = EQUIPMENT_FIELDS[eq.code] ?? [];
          const points = (pointsByEquipment[eq.id] ?? [])
            .filter((p) => allowedCodes.includes(p.code))
            .sort((a, b) => allowedCodes.indexOf(a.code) - allowedCodes.indexOf(b.code));

          if (points.length === 0) {
            return `
              <div class="equip-card" style="opacity:0.55;">
                <div class="equip-name">${eq.name}</div>
                <p class="empty-text" style="margin:4px 0;">Belum ada titik ukur terdaftar untuk equipment ini di master data.</p>
              </div>
            `;
          }

          return `
            <div class="equip-card">
              <div class="equip-name">${eq.name}</div>
              <div class="equip-fields">
                ${points.map(fieldValueHtml).join('')}
              </div>
            </div>
          `;
        })
        .join('')}

      <button class="btn-primary" id="btn-next" style="margin-top:6px;">Lanjut → Temperature Gearbox</button>
    </div>
  `;

  const back = root.querySelector('#btn-back');
  const goBack = () => navigate('/sheet-list');
  back.addEventListener('click', goBack);

  const nextBtn = root.querySelector('#btn-next');
  const goNext = () => navigate(`/breaker-input?sheetId=${sheetId}&round=${roundNumber}`);
  nextBtn.addEventListener('click', goNext);

  const numInputs = root.querySelectorAll('input[data-point-num]');
  const handleNumBlur = async (e) => {
    if (e.target.value === '') return;
    await saveReading({
      roundId,
      unitStatusId: null,
      measurementPointId: e.target.dataset.pointNum,
      valueNumeric: Number(e.target.value),
      recordedBy: user.id,
    });
  };
  numInputs.forEach((el) => el.addEventListener('blur', handleNumBlur));

  const textInputs = root.querySelectorAll('input[data-point-text]');
  const handleTextBlur = async (e) => {
    await saveReading({
      roundId,
      unitStatusId: null,
      measurementPointId: e.target.dataset.pointText,
      valueText: e.target.value,
      recordedBy: user.id,
    });
  };
  textInputs.forEach((el) => el.addEventListener('blur', handleTextBlur));

  const boolGroups = root.querySelectorAll('[data-point-bool]');
  const handleBoolClick = async (e) => {
    const btn = e.target.closest('button[data-bool]');
    if (!btn) return;
    const group = btn.closest('[data-point-bool]');
    const pointId = group.dataset.pointBool;
    const value = btn.dataset.bool === 'true';

    group.querySelectorAll('button').forEach((b) => b.classList.remove('selected'));
    btn.classList.add('selected');

    await saveReading({
      roundId,
      unitStatusId: null,
      measurementPointId: pointId,
      valueBoolean: value,
      recordedBy: user.id,
    });
  };
  boolGroups.forEach((el) => el.addEventListener('click', handleBoolClick));

  return () => {
    back.removeEventListener('click', goBack);
    nextBtn.removeEventListener('click', goNext);
    numInputs.forEach((el) => el.removeEventListener('blur', handleNumBlur));
    textInputs.forEach((el) => el.removeEventListener('blur', handleTextBlur));
    boolGroups.forEach((el) => el.removeEventListener('click', handleBoolClick));
  };
}
