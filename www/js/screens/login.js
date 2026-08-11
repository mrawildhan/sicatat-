import { login } from '../lib/auth.js';
import { navigate } from '../lib/router.js';

export function renderLogin(root) {
  root.innerHTML = `
    <div class="login-screen">
      <img src="assets/logo-full.png" alt="SICATAT" class="login-logo">

      <form id="login-form">
        <div class="field">
          <label>NIK</label>
          <input id="nik" type="text" inputmode="numeric" placeholder="Masukkan NIK Anda" required>
        </div>
        <div class="field">
          <label>PIN</label>
          <input id="pin" type="password" placeholder="••••" required>
        </div>
        <div id="login-error" class="error-text"></div>
        <button type="submit" class="btn-primary">Masuk</button>
      </form>
    </div>
  `;

  const form = root.querySelector('#login-form');
  const errorBox = root.querySelector('#login-error');

  const handleSubmit = async (e) => {
    e.preventDefault();
    errorBox.textContent = '';
    const nik = root.querySelector('#nik').value.trim();
    const pin = root.querySelector('#pin').value.trim();

    try {
      await login(nik, pin);
      navigate('/home');
    } catch (err) {
      errorBox.textContent = err.message;
    }
  };

  form.addEventListener('submit', handleSubmit);
  return () => form.removeEventListener('submit', handleSubmit); // cleanup untuk router.js
}
