import { navigate } from '../lib/router.js';

export function renderTemperatureMenu(root) {
  root.innerHTML = `
    <div class="topbar">
      <button class="btn-back" id="btn-back">← Home</div>
      <div class="topbar-title">Temperature</div>
    </div>
    <div class="screen-body">
      <div class="section-label">Choose a form</div>
      <div class="menu-card" id="btn-daily-check">
        <div>
          <div class="menu-card-label">Daily Temperature Check<br>Bearing Motor, etc.</div>
          <div class="menu-card-sub">Gearbox Breaker &amp; Sizer</div>
        </div>
        <div class="chevron">›</div>
      </div>
      <div class="menu-card disabled">
        <div>
          <div class="menu-card-label">Other areas</div>
          <div class="menu-card-sub">Coming soon</div>
        </div>
      </div>
    </div>
  `;

  const back = root.querySelector('#btn-back');
  const dailyCheck = root.querySelector('#btn-daily-check');
  const goBack = () => navigate('/home');
  const goToDailyCheck = () => navigate('/sheet-list');

  back.addEventListener('click', goBack);
  dailyCheck.addEventListener('click', goToDailyCheck);

  return () => {
    back.removeEventListener('click', goBack);
    dailyCheck.removeEventListener('click', goToDailyCheck);
  };
}
