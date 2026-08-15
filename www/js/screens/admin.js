import { navigate } from '../lib/router.js';

const MENU = [
  { label: 'Equipment', sub: 'List of equipment & measurement points', path: '/admin-equipment' },
  { label: 'Threshold', sub: 'Warning/alarm limits per measurement point', path: '/admin-threshold' },
  { label: 'Shift', sub: 'Day / Night, start-end time', path: '/admin-shift' },
  { label: 'Team', sub: 'Crew A / B / C', path: '/admin-team' },
  { label: 'Roster', sub: 'Crew rotation pattern (roster_anchor)', path: '/admin-roster' },
  { label: 'Crew', sub: 'Role, crew, active/inactive', path: '/admin-crew' },
  { label: 'Export Date Range', sub: 'Pull CSV data across crews for analysis', path: '/admin-export' },
];

export function renderAdmin(root) {
  root.innerHTML = `
    <div class="topbar">
      <button class="btn-back" id="btn-back">← Home</button>
      <div class="topbar-title">Manage Master Data</div>
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
