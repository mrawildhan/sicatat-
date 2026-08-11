import { supabase } from '../lib/supabase-client.js';
import { navigate } from '../lib/router.js';

// Bukan kalender roster harian -- tabel `roster` cuma cache hasil hitungan
// dari SINI (roster_anchor: tanggal mula + urutan regu, pola rotasi 3 hari
// Pagi -> 3 hari Malam -> 3 hari Off dihitung `hari_selisih mod 9`, lihat
// komentar di supabase/schema.sql). Admin cukup atur baris ini sekali.
export async function renderAdminRoster(root) {
  root.innerHTML = `<div class="screen-body"><p class="empty-text">Memuat...</p></div>`;

  let anchor;
  try {
    const { data, error } = await supabase
      .from('roster_anchor')
      .select('*')
      .eq('is_active', true)
      .order('tanggal_mula', { ascending: false })
      .limit(1);
    if (error) throw new Error(error.message);
    anchor = data?.[0] ?? null;
  } catch (err) {
    root.innerHTML = `<div class="screen-body"><div class="warn-box">Gagal memuat: ${err.message}</div></div>`;
    return () => {};
  }

  function draw() {
    const a = anchor ?? { tanggal_mula: '', urutan_regu: [] };
    root.innerHTML = `
      <div class="topbar">
        <button class="btn-back" id="btn-back">← Kelola Master Data</button>
        <div class="topbar-title">Roster</div>
      </div>
      <div class="screen-body">
        <div class="hint-text">
          Pola rotasi 3 hari Pagi → 3 hari Malam → 3 hari Off dihitung otomatis dari
          satu titik acuan ini, bukan diisi harian satu-satu.
        </div>

        ${!anchor ? '<div class="warn-box">Belum ada konfigurasi roster. Isi form di bawah untuk mengaktifkan.</div>' : ''}

        <div class="equip-card">
          <div class="field">
            <label>Tanggal mula siklus</label>
            <input id="f-tanggal" type="date" value="${a.tanggal_mula}">
          </div>
          <div class="field">
            <label>Urutan regu mengawali Pagi (pisah koma, mis. A,B,C)</label>
            <input id="f-urutan" type="text" value="${(a.urutan_regu ?? []).join(',')}">
          </div>
          <button class="btn-primary" id="f-save" style="margin-top:10px;">
            ${anchor ? 'Simpan Perubahan' : 'Aktifkan'}
          </button>
        </div>
      </div>
    `;

    const back = root.querySelector('#btn-back');
    back.addEventListener('click', () => navigate('/admin'));

    const saveBtn = root.querySelector('#f-save');
    saveBtn.addEventListener('click', async () => {
      const tanggalMula = root.querySelector('#f-tanggal').value;
      const urutanRegu = root.querySelector('#f-urutan').value.split(',').map((s) => s.trim()).filter(Boolean);
      if (!tanggalMula || urutanRegu.length === 0) { alert('Tanggal mula dan urutan regu wajib diisi.'); return; }

      try {
        if (anchor) {
          const { error } = await supabase
            .from('roster_anchor')
            .update({ tanggal_mula: tanggalMula, urutan_regu: urutanRegu })
            .eq('id', anchor.id);
          if (error) throw new Error(error.message);
        } else {
          // Baris lama (kalau ada, tidak aktif) dibiarkan sebagai riwayat --
          // cukup nonaktifkan yang lama & buat baru, jangan hapus permanen.
          await supabase.from('roster_anchor').update({ is_active: false }).eq('is_active', true);
          const { error } = await supabase
            .from('roster_anchor')
            .insert({ tanggal_mula: tanggalMula, urutan_regu: urutanRegu, is_active: true });
          if (error) throw new Error(error.message);
        }
        const { data, error: reErr } = await supabase
          .from('roster_anchor').select('*').eq('is_active', true)
          .order('tanggal_mula', { ascending: false }).limit(1);
        if (reErr) throw new Error(reErr.message);
        anchor = data?.[0] ?? null;
        alert('Tersimpan.');
        draw();
      } catch (err) {
        alert(`Gagal simpan: ${err.message}`);
      }
    });
  }

  draw();
  return () => {};
}
