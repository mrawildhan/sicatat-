// router.js — router hash sederhana. Sengaja tidak pakai framework (React/Vue)
// untuk MVP ini — sesuai keputusan "web dibungkus APK" yang mengutamakan
// kesederhanaan untuk solo developer (PRD-SICATAT-v0.4 Bagian 10).

const routes = {};
let currentCleanup = null;

export function register(path, renderFn) {
  routes[path] = renderFn;
}

export async function navigate(path) {
  window.location.hash = path;
}

async function render() {
  const path = window.location.hash.slice(1) || '/login';
  const renderFn = routes[path.split('?')[0]];
  const root = document.getElementById('app');

  if (typeof currentCleanup === 'function') {
    currentCleanup(); // lepas event listener layar sebelumnya, cegah kebocoran memori
    currentCleanup = null;
  }

  if (!renderFn) {
    root.innerHTML = `<p>Halaman tidak ditemukan: ${path}</p>`;
    return;
  }

  const params = new URLSearchParams(path.split('?')[1] || '');
  currentCleanup = await renderFn(root, params);
}

export function startRouter() {
  window.addEventListener('hashchange', render);
  render();
}
