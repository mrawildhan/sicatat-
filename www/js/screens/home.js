import { getCurrentUser, logout } from '../lib/auth.js';
import { navigate } from '../lib/router.js';

// Menu per peran — persis logika di wireframe Layar 0/0-fore/0-sup/0-adm.
// Ditulis sebagai data, bukan if/else bercabang di HTML, supaya menambah
// modul baru nanti (Peminjaman Barang, dst — lihat PRD Bagian 3.1) cukup
// menambah baris di sini.
function menuForRole(role) {
  const base = [
    { label: 'Temperature', sub: '1 form tersedia', path: '/temperature-menu', enabled: true },
  ];

  if (role === 'foreman' || role === 'supervisor' || role === 'admin') {
    base.push({
      label: 'Belum Lengkap',
      sub: role === 'foreman' ? 'Regu Anda saja' : 'Semua regu',
      path: '/incomplete-list',
      enabled: true,
    });
  }

  if (role === 'admin') {
    base.push({
      label: 'Kelola Master Data',
      sub: 'Crew, equipment, threshold, shift',
      path: '/admin',
      enabled: true,
    });
  }

  base.push({ label: 'Peminjaman Barang', sub: 'Segera hadir', path: null, enabled: false });
  return base;
}

export function renderHome(root) {
  const user = getCurrentUser();
  if (!user) {
    navigate('/login');
    return () => {};
  }

  const menu = menuForRole(user.role);

  root.innerHTML = `
    <div class="topbar topbar-with-logout">
      <div>
        <div class="topbar-label">SICATAT · ${user.role}</div>
        <div class="topbar-title">CPP Asam-Asam</div>
      </div>
      <button id="btn-logout" class="btn-logout">Keluar</button>
    </div>
    <div class="screen-body">
      <div class="section-label">Menu</div>
      ${menu
        .map(
          (m) => `
        <div class="menu-card ${m.enabled ? '' : 'disabled'}" data-path="${m.path ?? ''}">
          <div>
            <div class="menu-card-label">${m.label}</div>
            <div class="menu-card-sub">${m.sub}</div>
          </div>
          ${m.enabled ? '<div class="chevron">›</div>' : ''}
        </div>
      `
        )
        .join('')}
    </div>
  `;

  const logoutBtn = root.querySelector('#btn-logout');
  const handleLogout = async () => {
    const yakin = confirm('Keluar dari akun ini? Lembar yang belum tersinkron tetap tersimpan di HP ini.');
    if (!yakin) return;
    await logout();
    navigate('/login');
  };
  logoutBtn.addEventListener('click', handleLogout);

  const cards = root.querySelectorAll('.menu-card:not(.disabled)');
  const handleClick = (e) => {
    const path = e.currentTarget.dataset.path;
    if (path) navigate(path);
  };
  cards.forEach((c) => c.addEventListener('click', handleClick));

  return () => {
    logoutBtn.removeEventListener('click', handleLogout);
    cards.forEach((c) => c.removeEventListener('click', handleClick));
  };
}
