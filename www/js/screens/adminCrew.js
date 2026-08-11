import { supabase } from '../lib/supabase-client.js';
import { navigate } from '../lib/router.js';

const ROLES = ['crew', 'foreman', 'supervisor', 'admin'];

export async function renderAdminCrew(root) {
  root.innerHTML = `<div class="screen-body"><p class="empty-text">Memuat...</p></div>`;

  let users, teams;

  async function loadAll() {
    const { data: u, error: uErr } = await supabase.from('app_user').select('*, team:team_id(name)').order('name');
    if (uErr) throw new Error(uErr.message);
    users = u;
    const { data: t, error: tErr } = await supabase.from('team').select('*').eq('is_active', true).order('code');
    if (tErr) throw new Error(tErr.message);
    teams = t;
  }

  try {
    await loadAll();
  } catch (err) {
    root.innerHTML = `<div class="screen-body"><div class="warn-box">Gagal memuat: ${err.message}</div></div>`;
    return () => {};
  }

  let editingId = null; // null | 'new' | id
  let lastCreatedNik = null; // dipakai untuk tampilkan instruksi Auth setelah tambah baru

  function form(u) {
    const isNew = !u;
    const x = u ?? { nik: '', name: '', role: 'crew', team_id: teams[0]?.id ?? '', phone: '', is_active: true };
    const needsTeam = x.role === 'crew' || x.role === 'foreman';
    return `
      <div class="equip-card">
        ${isNew ? `<div class="warn-box">Ini cuma bikin baris data (app_user). Akun login (Supabase Auth) TETAP harus ditambahkan manual -- lihat instruksi setelah disimpan.</div>` : ''}
        <div class="field">
          <label>NIK</label>
          <input id="f-nik" type="text" value="${x.nik ?? ''}" ${isNew ? '' : 'disabled'}>
        </div>
        <div class="field">
          <label>Nama</label>
          <input id="f-name" type="text" value="${x.name}">
        </div>
        <div class="field">
          <label>Role</label>
          <select id="f-role">
            ${ROLES.map((r) => `<option value="${r}" ${x.role === r ? 'selected' : ''}>${r}</option>`).join('')}
          </select>
        </div>
        <div class="field" id="f-team-wrap" style="${needsTeam ? '' : 'display:none;'}">
          <label>Tim (wajib untuk crew/foreman)</label>
          <select id="f-team">
            ${teams.map((t) => `<option value="${t.id}" ${x.team_id === t.id ? 'selected' : ''}>${t.name}</option>`).join('')}
          </select>
        </div>
        <div class="field">
          <label>No. HP (opsional)</label>
          <input id="f-phone" type="text" value="${x.phone ?? ''}">
        </div>
        <label class="status-opt">
          <input type="checkbox" id="f-active" ${x.is_active ? 'checked' : ''}>
          Aktif
        </label>
        <button class="btn-primary" id="f-save" style="margin-top:10px;">${isNew ? 'Tambah Crew' : 'Simpan'}</button>
        <button class="btn-secondary" id="f-cancel">Batal</button>
      </div>
    `;
  }

  function draw() {
    root.innerHTML = `
      <div class="topbar">
        <button class="btn-back" id="btn-back">← Kelola Master Data</button>
        <div class="topbar-title">Crew</div>
      </div>
      <div class="screen-body">
        ${
          lastCreatedNik
            ? `<div class="warn-box">
                Baris data untuk NIK <strong>${lastCreatedNik}</strong> sudah dibuat. Supaya bisa login,
                tambahkan akun di Supabase Dashboard → Authentication → Users → Add user:<br>
                Email: <strong>${lastCreatedNik}@sicatat.local</strong><br>
                Password: PIN yang diinginkan crew ini.
              </div>`
            : ''
        }

        ${editingId === 'new' ? form(null) : ''}

        ${users
          .map((u) => {
            if (editingId === u.id) return form(u);
            return `
              <div class="sheet-card" data-id="${u.id}">
                <div>
                  <div class="sheet-date">${u.name}</div>
                  <div class="sheet-shift">NIK ${u.nik ?? '—'} · ${u.role}${u.team ? ' · ' + u.team.name : ''}</div>
                </div>
                <span class="pill ${u.is_active ? 'synced' : 'pending'}">${u.is_active ? 'Aktif' : 'Nonaktif'}</span>
              </div>
            `;
          })
          .join('')}

        ${editingId === null ? '<button class="btn-primary" id="btn-add" style="margin-top:10px;">+ Tambah Crew</button>' : ''}
      </div>
    `;

    const back = root.querySelector('#btn-back');
    back.addEventListener('click', () => navigate('/admin'));

    const addBtn = root.querySelector('#btn-add');
    if (addBtn) addBtn.addEventListener('click', () => { editingId = 'new'; lastCreatedNik = null; draw(); });

    root.querySelectorAll('.sheet-card').forEach((card) => {
      card.addEventListener('click', () => { editingId = card.dataset.id; lastCreatedNik = null; draw(); });
    });

    const cancelBtn = root.querySelector('#f-cancel');
    if (cancelBtn) cancelBtn.addEventListener('click', () => { editingId = null; draw(); });

    const roleSelect = root.querySelector('#f-role');
    if (roleSelect) {
      roleSelect.addEventListener('change', () => {
        const needsTeam = roleSelect.value === 'crew' || roleSelect.value === 'foreman';
        root.querySelector('#f-team-wrap').style.display = needsTeam ? '' : 'none';
      });
    }

    const saveBtn = root.querySelector('#f-save');
    if (saveBtn) {
      saveBtn.addEventListener('click', async () => {
        const nik = root.querySelector('#f-nik').value.trim();
        const name = root.querySelector('#f-name').value.trim();
        const role = root.querySelector('#f-role').value;
        const needsTeam = role === 'crew' || role === 'foreman';
        const teamId = needsTeam ? root.querySelector('#f-team').value : null;
        const phone = root.querySelector('#f-phone').value.trim() || null;
        const isActive = root.querySelector('#f-active').checked;
        if (!name || (editingId === 'new' && !nik)) { alert('NIK dan nama wajib diisi.'); return; }
        if (needsTeam && !teamId) { alert('Tim wajib diisi untuk role crew/foreman.'); return; }

        try {
          if (editingId === 'new') {
            const { error } = await supabase.from('app_user').insert({ nik, name, role, team_id: teamId, phone, is_active: isActive });
            if (error) throw new Error(error.message);
            lastCreatedNik = nik;
          } else {
            const { error } = await supabase.from('app_user')
              .update({ name, role, team_id: teamId, phone, is_active: isActive })
              .eq('id', editingId);
            if (error) throw new Error(error.message);
          }
          await loadAll();
          editingId = null;
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
