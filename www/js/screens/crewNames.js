import { saveContributors, getContributors } from '../lib/db.js';
import { getCurrentUser } from '../lib/auth.js';
import { navigate } from '../lib/router.js';
import { supabase } from '../lib/supabase-client.js';

// Muncul setelah Ronde 2 Gearbox Sizer selesai, sebelum Ringkasan (wireframe
// Layar 4c). SEMENTARA: sekali disimpan (klik Lanjut) tidak bisa diedit lagi
// -- lihat catatan di db.js saveContributors soal kenapa.
export async function renderCrewNames(root, params) {
  const sheetId = params.get('sheetId');
  const user = getCurrentUser();

  root.innerHTML = `<div class="screen-body"><p class="empty-text">Memuat...</p></div>`;

  let teamUsers, alreadySaved;
  try {
    // team_id NULL berarti user lintas tim (supervisor/admin) - tampilkan
    // semua crew aktif, bukan filter ke satu tim yang mereka tidak punya.
    let query = supabase.from('app_user').select('id, name').eq('is_active', true).order('name');
    if (user.team_id) query = query.eq('team_id', user.team_id);
    const { data, error } = await query;
    if (error) throw new Error(`Gagal ambil daftar crew: ${error.message}`);
    teamUsers = data;
    alreadySaved = await getContributors(sheetId);
  } catch (err) {
    root.innerHTML = `<div class="screen-body"><div class="warn-box">Gagal memuat: ${err.message}</div></div>`;
    return () => {};
  }

  const locked = alreadySaved.length > 0; // sudah pernah disimpan - lihat catatan di atas
  const selected = new Set(locked ? alreadySaved : [user.id]); // default: diri sendiri sudah tercentang

  function draw() {
    root.innerHTML = `
      <div class="topbar">
        <button class="btn-back" id="btn-back">← Gearbox Sizer</button>
        <div class="topbar-title">Nama Crew Pengisi</div>
      </div>
      <div class="screen-body">
        <div class="hint-text">Centang semua crew yang ikut mengisi lembar ini.</div>
        ${locked ? `<div class="warn-box">Sudah tersimpan, tidak bisa diubah lagi dari layar ini.</div>` : ''}

        ${teamUsers
          .map(
            (u) => `
          <label class="status-opt">
            <input type="checkbox" data-user="${u.id}" ${selected.has(u.id) ? 'checked' : ''} ${locked ? 'disabled' : ''}>
            ${u.name}${u.id === user.id ? ' (Anda)' : ''}
          </label>
        `
          )
          .join('')}

        ${selected.size === 0 ? `<div class="warn-box">Pilih minimal 1 orang sebelum lanjut.</div>` : ''}

        <button class="btn-primary" id="btn-next" style="margin-top:20px;" ${selected.size === 0 ? 'disabled style="opacity:0.4;"' : ''}>
          ${locked ? 'Lanjut → Ringkasan' : 'Simpan & Lanjut → Ringkasan'}
        </button>
      </div>
    `;

    const back = root.querySelector('#btn-back');
    back.addEventListener('click', () => navigate(`/breaker-input?sheetId=${sheetId}&round=2&section=gearbox_sizer`));

    if (!locked) {
      root.querySelectorAll('input[type="checkbox"]').forEach((cb) => {
        cb.addEventListener('change', () => {
          const id = cb.dataset.user;
          if (cb.checked) selected.add(id);
          else selected.delete(id);
          draw();
        });
      });
    }

    const nextBtn = root.querySelector('#btn-next');
    nextBtn.addEventListener('click', async () => {
      if (selected.size === 0) return;
      if (!locked) {
        await saveContributors(sheetId, [...selected]);
      }
      navigate(`/summary?sheetId=${sheetId}`);
    });
  }

  draw();
  return () => {};
}
