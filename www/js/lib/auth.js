// auth.js
//
// Login pakai Supabase Auth, BUKAN membandingkan PIN manual ke kolom tabel
// sendiri (itu berarti kita harus mengurus hashing password sendiri —
// area yang gampang salah kalau dibikin sendiri, jadi dipakaikan yang
// sudah teruji). Triknya: tiap NIK dipetakan jadi email sintetis
// "{nik}@sicatat.local", dan PIN dipakai sebagai password Supabase Auth.
//
// KONSEKUENSI SETUP: setiap akun di tabel `app_user` (Table Editor) HARUS
// punya pasangan akun di Supabase Authentication (dashboard > Authentication
// > Users > Add user), dengan email "{nik}@sicatat.local" dan password =
// PIN yang diinginkan. Dua tempat, satu akun — lihat README.

import { supabase } from './supabase-client.js';

let currentUser = null; // baris di tabel app_user, BUKAN objek auth Supabase

function nikToEmail(nik) {
  return `${nik.trim()}@sicatat.local`;
}

export async function login(nik, pin) {
  const { error: authError } = await supabase.auth.signInWithPassword({
    email: nikToEmail(nik),
    password: pin,
  });

  if (authError) {
    // Pesan Supabase asli ("Invalid login credentials") sengaja diganti
    // dengan bahasa yang lebih jelas untuk crew, tanpa membocorkan apakah
    // yang salah NIK atau PIN-nya (praktik keamanan standar).
    throw new Error('NIK atau PIN salah, atau akun belum aktif');
  }

  // Auth berhasil -> ambil profil lengkap (role, team_id, dll) dari app_user.
  const { data, error } = await supabase
    .from('app_user')
    .select('*')
    .eq('nik', nik.trim())
    .eq('is_active', true)
    .single();

  if (error || !data) {
    await supabase.auth.signOut(); // jangan biarkan sesi auth menggantung tanpa profil
    throw new Error('Akun ditemukan di Auth tapi tidak ada di app_user — hubungi admin');
  }

  currentUser = data;
  return currentUser;
}

export function getCurrentUser() {
  return currentUser;
}

// Dipanggil sekali saat aplikasi dibuka. Supabase Auth sudah otomatis
// menyimpan sesi login di penyimpanan lokal begitu login berhasil — bagian
// yang sebelumnya belum ada adalah MEMBACA sesi itu kembali. Kalau sesi
// masih valid, crew tidak perlu login ulang tiap buka aplikasi (FR-02).
export async function restoreSession() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.user?.email) return false;

  const nik = session.user.email.replace('@sicatat.local', '');
  const { data, error } = await supabase
    .from('app_user')
    .select('*')
    .eq('nik', nik)
    .eq('is_active', true)
    .single();

  if (error || !data) {
    await supabase.auth.signOut(); // sesi ada tapi profilnya tidak ketemu -> jangan setengah-setengah
    return false;
  }

  currentUser = data;
  return true;
}

export async function logout() {
  await supabase.auth.signOut();
  currentUser = null;
}

export function requireRole(...allowedRoles) {
  if (!currentUser) return false;
  return allowedRoles.includes(currentUser.role);
}