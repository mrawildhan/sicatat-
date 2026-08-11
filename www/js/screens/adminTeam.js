import { supabase } from '../lib/supabase-client.js';
import { navigate } from '../lib/router.js';

export async function renderAdminTeam(root) {
  root.innerHTML = `<div class="screen-body"><p class="empty-text">Memuat...</p></div>`;

  let teams;
  try {
    const { data, error } = await supabase.from('team').select('*').order('code');
    if (error) throw new Error(error.message);
    teams = data;
  } catch (err) {
    root.innerHTML = `<div class="screen-body"><div class="warn-box">Gagal memuat: ${err.message}</div></div>`;
    return () => {};
  }

  let editingId = null; // null = tidak ada form terbuka, 'new' = form tambah baru, id = form edit baris itu

  function blankForm(team) {
    const isNew = !team;
    const t = team ?? { code: '', name: '', is_active: true };
    return `
      <div class="equip-card">
        <div class="field">
          <label>Kode (mis. A)</label>
          <input id="f-code" type="text" value="${t.code}" maxlength="10">
        </div>
        <div class="field">
          <label>Nama (mis. Regu A)</label>
          <input id="f-name" type="text" value="${t.name}">
        </div>
        <label class="status-opt">
          <input type="checkbox" id="f-active" ${t.is_active ? 'checked' : ''}>
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
        <div class="topbar-title">Team</div>
      </div>
      <div class="screen-body">
        ${editingId === 'new' ? blankForm(null) : ''}

        ${teams
          .map((t) => {
            if (editingId === t.id) return blankForm(t);
            return `
              <div class="sheet-card" data-id="${t.id}">
                <div>
                  <div class="sheet-date">${t.name}</div>
                  <div class="sheet-shift">Kode: ${t.code}</div>
                </div>
                <span class="pill ${t.is_active ? 'synced' : 'pending'}">${t.is_active ? 'Aktif' : 'Nonaktif'}</span>
              </div>
            `;
          })
          .join('')}

        ${editingId === null ? '<button class="btn-primary" id="btn-add" style="margin-top:10px;">+ Tambah Team</button>' : ''}
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
        const isActive = root.querySelector('#f-active').checked;
        if (!code || !name) { alert('Kode dan nama wajib diisi.'); return; }

        try {
          if (editingId === 'new') {
            const { error } = await supabase.from('team').insert({ code, name, is_active: isActive });
            if (error) throw new Error(error.message);
          } else {
            const { error } = await supabase.from('team').update({ code, name, is_active: isActive }).eq('id', editingId);
            if (error) throw new Error(error.message);
          }
          const { data, error: reErr } = await supabase.from('team').select('*').order('code');
          if (reErr) throw new Error(reErr.message);
          teams = data;
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
