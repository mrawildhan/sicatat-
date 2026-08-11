// supabase-client.js
//
// GANTI dua nilai di bawah dengan milik project Supabase Bapak sendiri
// (Project Settings > API di dashboard Supabase). Jangan commit anon key
// project produksi ke repository publik — untuk MVP internal ini cukup
// disimpan di sini, tapi kalau repo di-share, pindahkan ke file .env.

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = 'https://ofczleeyqrxyuuupzirq.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_e85vPiEENe19yCviVUzuLg_nTewJBSW';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
