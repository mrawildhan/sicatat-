import { supabase } from '../lib/supabase-client.js';
import { navigate } from '../lib/router.js';

const SECTION_LABELS = { gearbox_breaker: 'Gearbox Breaker', gearbox_sizer: 'Gearbox Sizer' };
const DATA_TYPES = ['numeric', 'boolean', 'text'];

export async function renderAdminEquipment(root) {
  root.innerHTML = `<div class="screen-body"><p class="empty-text">Memuat...</p></div>`;

  let equipmentList, pointsByEquipment, sharedPoints;

  async function loadAll() {
    const { data: eq, error: eqErr } = await supabase.from('equipment').select('*').order('section').order('sort_order');
    if (eqErr) throw new Error(eqErr.message);
    equipmentList = eq;

    const { data: pts, error: ptErr } = await supabase.from('measurement_point').select('*').order('sort_order');
    if (ptErr) throw new Error(ptErr.message);
    pointsByEquipment = {};
    sharedPoints = [];
    for (const p of pts) {
      if (p.equipment_id) (pointsByEquipment[p.equipment_id] ??= []).push(p);
      else sharedPoints.push(p);
    }
  }

  try {
    await loadAll();
  } catch (err) {
    root.innerHTML = `<div class="screen-body"><div class="warn-box">Gagal memuat: ${err.message}</div></div>`;
    return () => {};
  }

  let editingEquipment = null; // null | 'new' | equipment id
  let newEquipmentSection = 'gearbox_breaker';
  let editingPoint = null; // null | { equipmentId: id|null, pointId: id|'new' }

  function equipmentForm(eq) {
    const isNew = !eq;
    const e = eq ?? { code: '', name: '', section: newEquipmentSection, sort_order: 0, is_active: true };
    return `
      <div class="equip-card">
        <div class="field">
          <label>Kode (mis. sizer_bearing)</label>
          <input id="eq-code" type="text" value="${e.code}">
        </div>
        <div class="field">
          <label>Nama tampil (mis. Bearing)</label>
          <input id="eq-name" type="text" value="${e.name}">
        </div>
        <div class="field">
          <label>Section</label>
          <select id="eq-section">
            ${Object.entries(SECTION_LABELS)
              .map(([v, l]) => `<option value="${v}" ${e.section === v ? 'selected' : ''}>${l}</option>`)
              .join('')}
          </select>
        </div>
        <div class="field">
          <label>Urutan tampil</label>
          <input id="eq-sort" type="number" value="${e.sort_order}">
        </div>
        <label class="status-opt">
          <input type="checkbox" id="eq-active" ${e.is_active ? 'checked' : ''}>
          Aktif
        </label>
        <button class="btn-primary" id="eq-save" style="margin-top:10px;">${isNew ? 'Tambah Equipment' : 'Simpan'}</button>
        <button class="btn-secondary" id="eq-cancel">Batal</button>
      </div>
    `;
  }

  function pointForm(point, equipmentId) {
    const isNew = !point;
    const p = point ?? { code: '', label: '', data_type: 'numeric', unit: '', is_required: true, sort_order: 0, is_active: true };
    return `
      <div class="equip-card" style="margin-left:16px; border-style:dashed;">
        <div class="point-fields">
          <div class="field">
            <label>Kode (mis. motor_de)</label>
            <input id="pt-code" type="text" value="${p.code}">
          </div>
          <div class="field">
            <label>Label (mis. Motor DE)</label>
            <input id="pt-label" type="text" value="${p.label}">
          </div>
        </div>
        <div class="point-fields">
          <div class="field">
            <label>Tipe data</label>
            <select id="pt-type">
              ${DATA_TYPES.map((t) => `<option value="${t}" ${p.data_type === t ? 'selected' : ''}>${t}</option>`).join('')}
            </select>
          </div>
          <div class="field">
            <label>Satuan (mis. °C, kosongkan jika bukan angka)</label>
            <input id="pt-unit" type="text" value="${p.unit ?? ''}">
          </div>
        </div>
        <label class="status-opt">
          <input type="checkbox" id="pt-required" ${p.is_required ? 'checked' : ''}>
          Wajib diisi
        </label>
        <label class="status-opt">
          <input type="checkbox" id="pt-active" ${p.is_active ? 'checked' : ''}>
          Aktif
        </label>
        <button class="btn-primary" id="pt-save" style="margin-top:10px;">${isNew ? 'Tambah Titik Ukur' : 'Simpan'}</button>
        <button class="btn-secondary" id="pt-cancel">Batal</button>
      </div>
    `;
  }

  function pointListHtml(points, equipmentId) {
    return `
      <div style="margin-left:16px; margin-top:6px;">
        ${points
          .map(
            (p) =>
              editingPoint?.equipmentId === equipmentId && editingPoint?.pointId === p.id
                ? pointForm(p, equipmentId)
                : `
              <div class="sheet-card" data-point-edit="${p.id}" data-equipment="${equipmentId ?? ''}" style="padding:8px 12px; margin-bottom:6px;">
                <div>
                  <div class="sheet-date" style="font-size:12px;">${p.label} <span style="color:var(--ink-soft); font-weight:400;">(${p.code})</span></div>
                  <div class="sheet-shift">${p.data_type}${p.unit ? ' · ' + p.unit : ''}${p.is_required ? '' : ' · opsional'}</div>
                </div>
                <span class="pill ${p.is_active ? 'synced' : 'pending'}">${p.is_active ? 'Aktif' : 'Nonaktif'}</span>
              </div>
            `
          )
          .join('')}
        ${
          editingPoint?.equipmentId === equipmentId && editingPoint?.pointId === 'new'
            ? pointForm(null, equipmentId)
            : `<button class="btn-secondary" data-add-point="${equipmentId ?? ''}" style="margin-bottom:10px;">+ Tambah Titik Ukur</button>`
        }
      </div>
    `;
  }

  function draw() {
    const bySection = { gearbox_breaker: [], gearbox_sizer: [] };
    for (const e of equipmentList) bySection[e.section]?.push(e);

    root.innerHTML = `
      <div class="topbar">
        <button class="btn-back" id="btn-back">← Kelola Master Data</button>
        <div class="topbar-title">Equipment</div>
      </div>
      <div class="screen-body">
        ${Object.entries(SECTION_LABELS)
          .map(
            ([section, label]) => `
          <div class="section-label">${label}</div>
          ${bySection[section]
            .map((e) =>
              editingEquipment === e.id
                ? equipmentForm(e)
                : `
              <div class="equip-card">
                <div class="sheet-card" data-eq-edit="${e.id}" style="border:none; padding:0; margin-bottom:0;">
                  <div>
                    <div class="sheet-date">${e.name}</div>
                    <div class="sheet-shift">Kode: ${e.code}</div>
                  </div>
                  <span class="pill ${e.is_active ? 'synced' : 'pending'}">${e.is_active ? 'Aktif' : 'Nonaktif'}</span>
                </div>
                ${pointListHtml(pointsByEquipment[e.id] ?? [], e.id)}
              </div>
            `
            )
            .join('')}
          ${
            editingEquipment === 'new' && newEquipmentSection === section
              ? equipmentForm(null)
              : `<button class="btn-secondary" data-add-equipment="${section}" style="margin-bottom:14px;">+ Tambah Equipment ${label}</button>`
          }
        `
          )
          .join('')}

        <div class="section-label">Titik Ukur Gearbox (Umum, bukan milik equipment tertentu)</div>
        <div class="equip-card">
          ${pointListHtml(sharedPoints, null)}
        </div>
      </div>
    `;

    const back = root.querySelector('#btn-back');
    back.addEventListener('click', () => navigate('/admin'));

    root.querySelectorAll('[data-eq-edit]').forEach((el) => {
      el.addEventListener('click', () => { editingEquipment = el.dataset.eqEdit; editingPoint = null; draw(); });
    });
    root.querySelectorAll('[data-add-equipment]').forEach((el) => {
      el.addEventListener('click', () => { editingEquipment = 'new'; newEquipmentSection = el.dataset.addEquipment; draw(); });
    });
    const eqCancel = root.querySelector('#eq-cancel');
    if (eqCancel) eqCancel.addEventListener('click', () => { editingEquipment = null; draw(); });
    const eqSave = root.querySelector('#eq-save');
    if (eqSave) {
      eqSave.addEventListener('click', async () => {
        const code = root.querySelector('#eq-code').value.trim();
        const name = root.querySelector('#eq-name').value.trim();
        const section = root.querySelector('#eq-section').value;
        const sortOrder = Number(root.querySelector('#eq-sort').value || 0);
        const isActive = root.querySelector('#eq-active').checked;
        if (!code || !name) { alert('Kode dan nama wajib diisi.'); return; }
        try {
          if (editingEquipment === 'new') {
            const { data: moduleRow, error: modErr } = await supabase.from('module').select('id').eq('code', 'temperature_check').single();
            if (modErr) throw new Error(modErr.message);
            const { error } = await supabase.from('equipment').insert({
              module_id: moduleRow.id, code, name, section, sort_order: sortOrder, is_active: isActive,
            });
            if (error) throw new Error(error.message);
          } else {
            const { error } = await supabase.from('equipment')
              .update({ code, name, section, sort_order: sortOrder, is_active: isActive })
              .eq('id', editingEquipment);
            if (error) throw new Error(error.message);
          }
          await loadAll();
          editingEquipment = null;
          draw();
        } catch (err) {
          alert(`Gagal simpan: ${err.message}`);
        }
      });
    }

    root.querySelectorAll('[data-point-edit]').forEach((el) => {
      el.addEventListener('click', () => {
        editingPoint = { equipmentId: el.dataset.equipment || null, pointId: el.dataset.pointEdit };
        editingEquipment = null;
        draw();
      });
    });
    root.querySelectorAll('[data-add-point]').forEach((el) => {
      el.addEventListener('click', () => {
        editingPoint = { equipmentId: el.dataset.addPoint || null, pointId: 'new' };
        draw();
      });
    });
    const ptCancel = root.querySelector('#pt-cancel');
    if (ptCancel) ptCancel.addEventListener('click', () => { editingPoint = null; draw(); });
    const ptSave = root.querySelector('#pt-save');
    if (ptSave) {
      ptSave.addEventListener('click', async () => {
        const code = root.querySelector('#pt-code').value.trim();
        const label = root.querySelector('#pt-label').value.trim();
        const dataType = root.querySelector('#pt-type').value;
        const unit = root.querySelector('#pt-unit').value.trim() || null;
        const isRequired = root.querySelector('#pt-required').checked;
        const isActive = root.querySelector('#pt-active').checked;
        if (!code || !label) { alert('Kode dan label wajib diisi.'); return; }
        try {
          const payload = { code, label, data_type: dataType, unit, is_required: isRequired, is_active: isActive };
          if (editingPoint.pointId === 'new') {
            await supabase.from('measurement_point').insert({ ...payload, equipment_id: editingPoint.equipmentId, sort_order: 0 })
              .then(({ error }) => { if (error) throw new Error(error.message); });
          } else {
            await supabase.from('measurement_point').update(payload).eq('id', editingPoint.pointId)
              .then(({ error }) => { if (error) throw new Error(error.message); });
          }
          await loadAll();
          editingPoint = null;
          draw();
        } catch (err) {
          alert(`Gagal simpan: ${err.message}`);
        }
      });
    }
  }

  draw();
  return () => {};
}
