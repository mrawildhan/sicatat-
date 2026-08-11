import { supabase } from '../lib/supabase-client.js';
import { getCurrentUser } from '../lib/auth.js';
import { navigate } from '../lib/router.js';
import { EXPECTED_SIDES } from './summary.js';

// Wireframe Layar 6. Query LANGSUNG ke Supabase, bukan SQLite lokal --
// tujuan layar ini melihat lembar milik crew lain di device lain, yang
// tidak pernah ada di database lokal device ini. Sengaja TANPA drill-down
// ke detail per-sisi (lihat catatan di summary.js: layar itu baca dari
// SQLite lokal, tidak bisa dipakai untuk lembar milik device lain).
export async function renderIncompleteList(root) {
  const user = getCurrentUser();
  const scopedToOwnTeam = user.role === 'foreman';

  root.innerHTML = `<div class="screen-body"><p class="empty-text">Memuat...</p></div>`;

  let sheets;
  try {
    let query = supabase
      .from('sheet')
      .select('id, tanggal, status, team:team_id(name), shift:shift_id(code)')
      .in('status', ['draft', 'submitted_incomplete'])
      .order('tanggal', { ascending: false });
    if (scopedToOwnTeam) query = query.eq('team_id', user.team_id);
    const { data, error } = await query;
    if (error) throw new Error(`Gagal ambil daftar lembar: ${error.message}`);
    sheets = data;
  } catch (err) {
    root.innerHTML = `<div class="screen-body"><div class="warn-box">Gagal memuat: ${err.message}</div></div>`;
    return () => {};
  }

  // Untuk tiap lembar, hitung berapa sisi BARAT/TIMUR yang sudah dijawab
  // (status IS NOT NULL). Ronde yang belum pernah dibuka sama sekali tidak
  // punya baris round/unit_status -- otomatis kehitung "belum diisi" karena
  // completed tidak pernah menghitungnya, sementara total tetap tetap.
  const rows = [];
  for (const sheet of sheets) {
    const { data: rounds } = await supabase.from('round').select('id').eq('sheet_id', sheet.id);
    const roundIds = (rounds ?? []).map((r) => r.id);
    let completed = 0;
    if (roundIds.length > 0) {
      const { count } = await supabase
        .from('unit_status')
        .select('id', { count: 'exact', head: true })
        .in('round_id', roundIds)
        .not('unit_code', 'is', null)
        .not('status', 'is', null);
      completed = count ?? 0;
    }
    rows.push({ ...sheet, completed, total: EXPECTED_SIDES.length });
  }

  root.innerHTML = `
    <div class="topbar">
      <button class="btn-back" id="btn-back">← Beranda</button>
      <div class="topbar-title">Belum Lengkap</div>
    </div>
    <div class="screen-body">
      <div class="hint-text">${scopedToOwnTeam ? 'Regu Anda saja' : 'Semua regu'}</div>
      ${
        rows.length === 0
          ? '<p class="empty-text">Tidak ada lembar belum lengkap.</p>'
          : rows
              .map(
                (r) => `
            <div class="sheet-card">
              <div>
                <div class="sheet-date">${r.tanggal}</div>
                <div class="sheet-shift">${r.team?.name ?? '—'} · ${r.shift?.code ?? '—'}</div>
              </div>
              <span class="pill ${r.status === 'submitted_incomplete' ? 'pending' : 'draft'}">
                ${r.completed}/${r.total} · ${r.status === 'submitted_incomplete' ? 'Override' : 'Draft'}
              </span>
            </div>
          `
              )
              .join('')
      }
    </div>
  `;

  const back = root.querySelector('#btn-back');
  const goBack = () => navigate('/home');
  back.addEventListener('click', goBack);

  return () => {
    back.removeEventListener('click', goBack);
  };
}
