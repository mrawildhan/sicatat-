import { supabase } from '../lib/supabase-client.js';
import { navigate } from '../lib/router.js';

export async function renderAdminShift(root) {
  root.innerHTML = `<div class="screen-body"><p class="empty-text">Memuat...</p></div>`;

  let shifts;
  try {
    const { data, error } = await supabase.from('shift').select('*').order('code');
    if (error) throw new Error(error.message);
    shifts = data;
  } catch (err) {
    root.innerHTML = `<div class="screen-body"><div class="warn-box">Gagal memuat: ${err.message}</div></div>`;
    return () => {};
  }

  let editingId = null;

  function blankForm(shift) {
    const isNew = !shift;
    const s = shift ?? { code: '', name: '', start_time: '', end_time: '', is_active: true };
    return `
      <div class="equip-card">
        <div class="field">
          <label>Kode (mis. PAGI)</label>
          <input id="f-code" type="text" value="${s.code}" maxlength="10">
        </div>
        <div class="field">
          <label>Nama (mis. Shift Pagi)</label>
          <input id="f-name" type="text" value="${s.name}">
        </div>
        <div class="point-fields">
          <div class="field">
            <label>Jam mulai</label>
            <input id="f-start" type="time" value="${s.start_time?.slice(0, 5) ?? ''}">
          </div>
          <div class="field">
            <label>Jam selesai</label>
            <input id="f-end" type="time" value="${s.end_time?.slice(0, 5) ?? ''}">
          </div>
        </div>
        <label class="status-opt">
          <input type="checkbox" id="f-active" ${s.is_active ? 'checked' : ''}>
          Aktif
        </label>
        <button class="btn-primary" id="f-save" style="margin-top:10px;">${isNew ? 'Tambah' : 'Simpan'}</button>
        <button class="btn-secondary" id="f-cancel">Batal</button>
      </div>
    `;
  }

  async function draw() {
    root.innerHTML = `
      <div class="topbar">
        <button class="btn-back" id="btn-back">← Kelola Master Data</button>
        <div class="topbar-title">Shift</div>
      </div>
      <div class="screen-body">
        ${editingId === 'new' ? blankForm(null) : ''}

        ${shifts
          .map((s) => {
            if (editingId === s.id) return blankForm(s);
            return `
              <div class="sheet-card" data-id="${s.id}">
                <div>
                  <div class="sheet-date">${s.name}</div>
                  <div class="sheet-shift">${s.code} · ${s.start_time?.slice(0, 5)}–${s.end_time?.slice(0, 5)}</div>
                </div>
                <span class="pill ${s.is_active ? 'synced' : 'pending'}">${s.is_active ? 'Aktif' : 'Nonaktif'}</span>
              </div>
            `;
          })
          .join('')}

        ${editingId === null ? '<button class="btn-primary" id="btn-add" style="margin-top:10px;">+ Tambah Shift</button>' : ''}
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
        const code = root.querySelector('#f-code').value.trim();
        const name = root.querySelector('#f-name').value.trim();
        const startTime = root.querySelector('#f-start').value;
        const endTime = root.querySelector('#f-end').value;
        const isActive = root.querySelector('#f-active').checked;
        if (!code || !name || !startTime || !endTime) { alert('Semua field wajib diisi.'); return; }

        try {
          const payload = { code, name, start_time: startTime, end_time: endTime, is_active: isActive };
          if (editingId === 'new') {
            const { error } = await supabase.from('shift').insert(payload);
            if (error) throw new Error(error.message);
          } else {
            const { error } = await supabase.from('shift').update(payload).eq('id', editingId);
            if (error) throw new Error(error.message);
          }
          const { data, error: reErr } = await supabase.from('shift').select('*').order('code');
          if (reErr) throw new Error(reErr.message);
          shifts = data;
          editingId = null;
          draw();
        } catch (err) {
          alert(`Gagal simpan: ${err.message}`);
        }
      });
    }
  }

  await draw();
  return () => {};
}
