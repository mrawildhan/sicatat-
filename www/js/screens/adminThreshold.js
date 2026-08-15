import { supabase } from '../lib/supabase-client.js';
import { navigate } from '../lib/router.js';

export async function renderAdminThreshold(root) {
  root.innerHTML = `<div class="screen-body"><p class="empty-text">Loading...</p></div>`;

  let thresholds, points;

  async function loadAll() {
    const { data: pts, error: ptErr } = await supabase
      .from('measurement_point')
      .select('id, code, label, unit, equipment:equipment_id(name)')
      .eq('is_active', true)
      .order('code');
    if (ptErr) throw new Error(ptErr.message);
    points = pts;

    const { data: th, error: thErr } = await supabase
      .from('threshold')
      .select('*, measurement_point:measurement_point_id(label, code, equipment:equipment_id(name))')
      .order('effective_from', { ascending: false });
    if (thErr) throw new Error(thErr.message);
    thresholds = th;
  }

  try {
    await loadAll();
  } catch (err) {
    root.innerHTML = `<div class="screen-body"><div class="warn-box">Failed to load: ${err.message}</div></div>`;
    return () => {};
  }

  function pointLabel(mp) {
    if (!mp) return '—';
    return mp.equipment ? `${mp.equipment.name} · ${mp.label}` : mp.label;
  }

  let editingId = null; // null | 'new' | id

  function form(t) {
    const isNew = !t;
    const x = t ?? { measurement_point_id: points[0]?.id ?? '', warning_min: '', warning_max: '', alarm_min: '', alarm_max: '', delta_max_per_round: '', source_note: '', is_active: true };
    return `
      <div class="equip-card">
        <div class="field">
          <label>Measurement point</label>
          <select id="f-point">
            ${points.map((p) => `<option value="${p.id}" ${x.measurement_point_id === p.id ? 'selected' : ''}>${pointLabel({ ...p })}</option>`).join('')}
          </select>
        </div>
        <div class="point-fields">
          <div class="field">
            <label>Warning min</label>
            <input id="f-wmin" type="number" step="0.1" value="${x.warning_min ?? ''}">
          </div>
          <div class="field">
            <label>Warning max</label>
            <input id="f-wmax" type="number" step="0.1" value="${x.warning_max ?? ''}">
          </div>
        </div>
        <div class="point-fields">
          <div class="field">
            <label>Alarm min</label>
            <input id="f-amin" type="number" step="0.1" value="${x.alarm_min ?? ''}">
          </div>
          <div class="field">
            <label>Alarm max</label>
            <input id="f-amax" type="number" step="0.1" value="${x.alarm_max ?? ''}">
          </div>
        </div>
        <div class="field">
          <label>Max jump between rounds (delta)</label>
          <input id="f-delta" type="number" step="0.1" value="${x.delta_max_per_round ?? ''}">
        </div>
        <div class="field">
          <label>Source (required -- OEM manual, engineering, etc.)</label>
          <input id="f-note" type="text" value="${x.source_note ?? ''}">
        </div>
        <label class="status-opt">
          <input type="checkbox" id="f-active" ${x.is_active ? 'checked' : ''}>
          Active
        </label>
        <button class="btn-primary" id="f-save" style="margin-top:10px;">${isNew ? 'Add Threshold' : 'Save'}</button>
        <button class="btn-secondary" id="f-cancel">Cancel</button>
      </div>
    `;
  }

  function draw() {
    root.innerHTML = `
      <div class="topbar">
        <button class="btn-back" id="btn-back">← Manage Master Data</button>
        <div class="topbar-title">Threshold</div>
      </div>
      <div class="screen-body">
        ${points.length === 0 ? '<div class="warn-box">No active measurement points yet -- add one in the Equipment menu first.</div>' : ''}

        ${editingId === 'new' ? form(null) : ''}

        ${thresholds
          .map((t) => {
            if (editingId === t.id) return form(t);
            return `
              <div class="sheet-card" data-id="${t.id}">
                <div>
                  <div class="sheet-date">${pointLabel(t.measurement_point)}</div>
                  <div class="sheet-shift">Warning ${t.warning_min ?? '—'}–${t.warning_max ?? '—'} · Alarm ${t.alarm_min ?? '—'}–${t.alarm_max ?? '—'}</div>
                </div>
                <span class="pill ${t.is_active ? 'synced' : 'pending'}">${t.is_active ? 'Active' : 'Inactive'}</span>
              </div>
            `;
          })
          .join('')}

        ${editingId === null && points.length > 0 ? '<button class="btn-primary" id="btn-add" style="margin-top:10px;">+ Add Threshold</button>' : ''}
      </div>
    `;

    const back = root.querySelector('#btn-back');
    back.addEventListener('click', () => navigate('/admin'));

    const addBtn = root.querySelector('#btn-add');
    if (addBtn) addBtn.addEventListener('click', () => { editingId = 'new'; draw(); });

    root.querySelectorAll('.sheet-card').forEach((card) => {
      card.addEventListener('click', () => { editingId = card.dataset.id; draw(); });
    });

    const cancelBtn = root.querySelector('#f-cancel');
    if (cancelBtn) cancelBtn.addEventListener('click', () => { editingId = null; draw(); });

    const saveBtn = root.querySelector('#f-save');
    if (saveBtn) {
      saveBtn.addEventListener('click', async () => {
        const measurementPointId = root.querySelector('#f-point').value;
        const sourceNote = root.querySelector('#f-note').value.trim();
        if (!sourceNote) { alert('Source is required -- don\'t leave it blank (see schema notes).'); return; }
        const num = (id) => {
          const v = root.querySelector(id).value;
          return v === '' ? null : Number(v);
        };
        const payload = {
          measurement_point_id: measurementPointId,
          warning_min: num('#f-wmin'), warning_max: num('#f-wmax'),
          alarm_min: num('#f-amin'), alarm_max: num('#f-amax'),
          delta_max_per_round: num('#f-delta'),
          source_note: sourceNote,
          is_active: root.querySelector('#f-active').checked,
        };
        try {
          if (editingId === 'new') {
            const { error } = await supabase.from('threshold').insert(payload);
            if (error) throw new Error(error.message);
          } else {
            const { error } = await supabase.from('threshold').update(payload).eq('id', editingId);
            if (error) throw new Error(error.message);
          }
          await loadAll();
          editingId = null;
          draw();
        } catch (err) {
          alert(`Failed to save: ${err.message}`);
        }
      });
    }
  }

  draw();
  return () => {};
}
