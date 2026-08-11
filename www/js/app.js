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

  // Layar berikut ADA di PRD & wireframe (sizer input, nama crew, ringkasan,
  // jalur override supervisor, monitoring belum lengkap, admin) tapi BELUM
  // ditulis kodenya — lihat README.md bagian "Yang belum dikerjakan".

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
