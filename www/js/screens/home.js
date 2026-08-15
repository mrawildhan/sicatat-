import { getCurrentUser, logout } from '../lib/auth.js';
import { navigate } from '../lib/router.js';
import { supabase } from '../lib/supabase-client.js';

// Menu per peran — persis logika di wireframe Layar 0/0-fore/0-sup/0-adm.
// Ditulis sebagai data, bukan if/else bercabang di HTML, supaya menambah
// modul baru nanti cukup menambah baris di sini.
function menuForRole(role) {
  const base = [
    { label: 'Temperature', sub: '1 form available', path: '/temperature-menu', enabled: true },
  ];

  if (role === 'foreman' || role === 'supervisor' || role === 'admin') {
    base.push({
      label: 'Incomplete',
      sub: role === 'foreman' ? 'Your crew only' : 'All crews',
      path: '/incomplete-list',
      enabled: true,
    });
    base.push({
      label: 'High Temperature Report',
      sub: '≥60°C across all crews',
      path: '/high-temp-report',
      enabled: true,
    });
  }

  if (role === 'admin') {
    base.push({
      label: 'Manage Master Data',
      sub: 'Crew, equipment, threshold, shift',
      path: '/admin',
      enabled: true,
    });
  }

  return base;
}

function capitalize(s) {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export async function renderHome(root) {
  const user = getCurrentUser();
  if (!user) {
    navigate('/login');
    return () => {};
  }

  const menu = menuForRole(user.role);

  // Kode regu (mis. "A") cuma relevan utk crew/foreman (punya team_id) --
  // supervisor/admin lintas regu, jadi label peran mereka tetap generik.
  // Gagal diam-diam kalau offline -- label tetap tampil tanpa kode regu.
  let teamCode = null;
  if (user.team_id) {
    try {
      const { data } = await supabase.from('team').select('code').eq('id', user.team_id).single();
      teamCode = data?.code ?? null;
    } catch {
      teamCode = null;
    }
  }
  const roleLabel = teamCode ? `${capitalize(user.role)} ${teamCode}` : capitalize(user.role);

  root.innerHTML = `
    <div class="topbar topbar-with-logout">
      <div class="topbar-identity">
        <img src="assets/logo-icon.png" alt="SICATAT" class="topbar-logo">
        <div>
          <div class="topbar-label">SICATAT · ${roleLabel}</div>
          <div class="topbar-title">CPP Asam-Asam</div>
          <div class="topbar-user">${user.name}</div>
        </div>
      </div>
      <button id="btn-logout" class="btn-logout">Log out</button>
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
    const yakin = confirm('Log out of this account? Sheets that haven\'t synced yet will stay saved on this phone.');
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
