import { register, startRouter } from './lib/router.js';
import { initDb } from './lib/db.js';
import { watchConnectivity, syncNow } from './lib/sync-engine.js';
import { watchConnectivityGate } from './lib/connectivity-gate.js';
import { restoreSession } from './lib/auth.js';
import { renderLogin } from './screens/login.js';
import { renderHome } from './screens/home.js';
import { renderTemperatureMenu } from './screens/temperatureMenu.js';
import { renderSheetList } from './screens/sheetList.js';
import { renderEquipmentInput } from './screens/equipmentInput.js';
import { renderBreakerInput } from './screens/breakerInput.js';
import { renderSummary } from './screens/summary.js';
import { renderIncompleteList } from './screens/incompleteList.js';
import { renderAdmin } from './screens/admin.js';
import { renderAdminEquipment } from './screens/adminEquipment.js';
import { renderAdminThreshold } from './screens/adminThreshold.js';
import { renderAdminShift } from './screens/adminShift.js';
import { renderAdminTeam } from './screens/adminTeam.js';
import { renderAdminRoster } from './screens/adminRoster.js';
import { renderAdminCrew } from './screens/adminCrew.js';
import { renderAdminExport } from './screens/adminExport.js';
import { renderHighTempReport } from './screens/highTempReport.js';
import { checkAppVersion, APP_VERSION } from './lib/version.js';

// FR-57: overlay penuh yang menutupi app, tidak ada tombol lanjut. Cuma
// dipanggil kalau server KONFIRMASI versi ini di bawah minimum -- lihat
// catatan fail-open di lib/version.js.
function showVersionBlock(info) {
  const overlay = document.createElement('div');
  overlay.style.cssText = 'position:fixed; inset:0; background:#fff; z-index:9999; padding:40px 24px; text-align:center; font-family:-apple-system,"Segoe UI",Roboto,Arial,sans-serif;';
  overlay.innerHTML = `
    <div style="font-size:17px; font-weight:700; margin-bottom:10px;">Update Required</div>
    <div style="font-size:13px; color:#5c645c; line-height:1.6;">
      This app version (${info.currentVersion}) is no longer supported.
      Ask your admin for the latest APK (${info.latestVersion}) before continuing.
      ${info.releaseNotes ? `<br><br>${info.releaseNotes}` : ''}
    </div>
  `;
  document.body.appendChild(overlay);
}

// FR-56: pemberitahuan ringan, tidak menghalangi pemakaian app.
function showUpdateAvailableNotice(info) {
  alert(`A new version (${info.latestVersion}) is available. The app still works, but ask your admin to update it when you get a chance.`);
}

async function bootstrap() {
  // Item #10: paling awal, sebelum apa pun lain -- kalau app dibuka offline,
  // overlay blocking langsung muncul duluan sebelum sempat render layar apa
  // pun (lihat lib/connectivity-gate.js untuk kenapa app ini sekarang
  // online-only, bukan lagi offline-first).
  watchConnectivityGate();

  await initDb();

  register('/login', renderLogin);
  register('/home', renderHome);
  register('/temperature-menu', renderTemperatureMenu);
  register('/sheet-list', renderSheetList);
  register('/breaker-equipment', renderEquipmentInput);
  register('/breaker-input', renderBreakerInput);
  register('/summary', renderSummary);
  register('/incomplete-list', renderIncompleteList);
  register('/admin', renderAdmin);
  register('/admin-equipment', renderAdminEquipment);
  register('/admin-threshold', renderAdminThreshold);
  register('/admin-shift', renderAdminShift);
  register('/admin-team', renderAdminTeam);
  register('/admin-roster', renderAdminRoster);
  register('/admin-crew', renderAdminCrew);
  register('/admin-export', renderAdminExport);
  register('/high-temp-report', renderHighTempReport);

  // Cek dulu apakah ada sesi login tersimpan SEBELUM router pertama kali
  // menggambar layar — supaya tidak sempat kelihatan kedip ke layar Login
  // dulu baru pindah ke Beranda.
  const hasSession = await restoreSession();
  if (hasSession && !window.location.hash) {
    window.location.hash = '/home';
  }

  startRouter();
  watchConnectivity();
  syncNow(); // coba sinkron begitu app dibuka, kalau kebetulan online

  // Jalan di belakang, TIDAK menunda render pertama -- app offline-first
  // harus tetap cepat dibuka meski cek versi lambat/gagal (lihat lib/version.js).
  checkAppVersion().then((info) => {
    if (info.blocked) showVersionBlock({ ...info, currentVersion: APP_VERSION });
    else if (info.updateAvailable) showUpdateAvailableNotice(info);
  });
}

bootstrap();
