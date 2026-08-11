import { register, startRouter } from './lib/router.js';
import { initDb } from './lib/db.js';
import { watchConnectivity, syncNow } from './lib/sync-engine.js';
import { restoreSession } from './lib/auth.js';
import { renderLogin } from './screens/login.js';
import { renderHome } from './screens/home.js';
import { renderTemperatureMenu } from './screens/temperatureMenu.js';
import { renderSheetList } from './screens/sheetList.js';
import { renderEquipmentInput } from './screens/equipmentInput.js';
import { renderBreakerInput } from './screens/breakerInput.js';
import { renderCrewNames } from './screens/crewNames.js';
import { renderSummary } from './screens/summary.js';
import { renderIncompleteList } from './screens/incompleteList.js';
import { renderAdmin } from './screens/admin.js';
import { renderAdminEquipment } from './screens/adminEquipment.js';
import { renderAdminThreshold } from './screens/adminThreshold.js';
import { renderAdminShift } from './screens/adminShift.js';
import { renderAdminTeam } from './screens/adminTeam.js';
import { renderAdminRoster } from './screens/adminRoster.js';
import { renderAdminCrew } from './screens/adminCrew.js';

async function bootstrap() {
  await initDb();

  register('/login', renderLogin);
  register('/home', renderHome);
  register('/temperature-menu', renderTemperatureMenu);
  register('/sheet-list', renderSheetList);
  register('/breaker-equipment', renderEquipmentInput);
  register('/breaker-input', renderBreakerInput);
  register('/crew-names', renderCrewNames);
  register('/summary', renderSummary);
  register('/incomplete-list', renderIncompleteList);
  register('/admin', renderAdmin);
  register('/admin-equipment', renderAdminEquipment);
  register('/admin-threshold', renderAdminThreshold);
  register('/admin-shift', renderAdminShift);
  register('/admin-team', renderAdminTeam);
  register('/admin-roster', renderAdminRoster);
  register('/admin-crew', renderAdminCrew);

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
}

bootstrap();
