import { navigate } from '../lib/router.js';

const MENU = [
  { label: 'Equipment', sub: 'Daftar equipment & titik ukur', path: '/admin-equipment' },
  { label: 'Threshold', sub: 'Batas warning/alarm per titik ukur', path: '/admin-threshold' },
  { label: 'Shift', sub: 'Pagi / Malam, jam mulai-selesai', path: '/admin-shift' },
  { label: 'Team', sub: 'Regu A / B / C', path: '/admin-team' },
  { label: 'Roster', sub: 'Pola rotasi regu (roster_anchor)', path: '/admin-roster' },
  { label: 'Crew', sub: 'Role, tim, aktif/nonaktif', path: '/admin-crew' },
  { label: 'Ekspor Rentang Tanggal', sub: 'Tarik data CSV lintas regu untuk analisa', path: '/admin-export' },
];

export function renderAdmin(root) {
  root.innerHTML = `
    <div class="topbar">
      <button class="btn-back" id="btn-back">← Beranda</button>
      <div class="topbar-title">Kelola Master Data</div>
    </div>
    <div class="screen-body">
      ${MENU.map(
        (m) => `
        <div class="menu-card" data-path="${m.path}">
          <div>
            <div class="menu-card-label">${m.label}</div>
            <div class="menu-card-sub">${m.sub}</div>
          </div>
          <div class="chevron">›</div>
        </div>
      `
      ).join('')}
    </div>
  `;

  const back = root.querySelector('#btn-back');
  const goBack = () => navigate('/home');
  back.addEventListener('click', goBack);

  const cards = root.querySelectorAll('.menu-card');
  const handleClick = (e) => navigate(e.currentTarget.dataset.path);
  cards.forEach((c) => c.addEventListener('click', handleClick));

  return () => {
    back.removeEventListener('click', goBack);
    cards.forEach((c) => c.removeEventListener('click', handleClick));
  };
}
