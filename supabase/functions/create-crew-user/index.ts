// create-crew-user — bikin akun SICATAT baru SEKALIGUS:
// akun Supabase Auth (login) + baris app_user (profil), dalam satu panggilan
// dari app (Admin -> Crew -> Tambah Crew), tanpa buka Supabase Dashboard.
//
// Kenapa harus lewat Edge Function, bukan langsung dari app: bikin akun Auth
// baru (auth.admin.createUser) cuma bisa pakai SERVICE ROLE KEY, yang TIDAK
// BOLEH ditaruh di app client (APK bisa di-decompile, kunci itu akan bocor
// dan memberi akses penuh ke seluruh database). Function ini jalan di server
// Supabase, pegang service role key dengan aman lewat env var bawaan
// (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY -- otomatis
// tersedia di runtime, tidak perlu di-set manual).
//
// Caller HARUS admin yang sedang login (dicek dari JWT di header Authorization
// yang otomatis disertakan oleh supabase.functions.invoke() di client).

import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const VALID_ROLES = [
  'crew',
  'foreman',
  'supervisor_cop',
  'supervisor_smg',
  'foreman_lv',
  'admin',
];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  try {
    // ---- 1. Identifikasi & otorisasi caller (harus admin aktif) ----
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ ok: false, error: 'No login session.' }, 401);

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user: authUser }, error: authError } = await callerClient.auth.getUser();
    if (authError || !authUser?.email) {
      return json({ ok: false, error: 'Invalid session, please log in again.' }, 401);
    }
    const callerNik = authUser.email.replace('@sicatat.local', '');

    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: callerProfile, error: callerErr } = await admin
      .from('app_user')
      .select('role, is_active')
      .eq('nik', callerNik)
      .single();
    if (callerErr || !callerProfile || callerProfile.role !== 'admin' || !callerProfile.is_active) {
      return json({ ok: false, error: 'Only admins can add accounts.' }, 403);
    }

    // ---- 2. Validasi input ----
    const body = await req.json().catch(() => ({}));
    const nik = String(body.nik ?? '').trim();
    const name = String(body.name ?? '').trim();
    const role = String(body.role ?? '').trim();
    const teamId = body.team_id || null;
    const siteId = body.site_id || null;
    const phone = body.phone || null;
    const pin = String(body.pin ?? '').trim();

    if (!nik || !name || !role || !pin) {
      return json({ ok: false, error: 'NIK, name, role, and PIN are required.' }, 400);
    }
    if (!VALID_ROLES.includes(role)) {
      return json({ ok: false, error: 'Invalid role.' }, 400);
    }
    if ((role === 'crew' || role === 'foreman') && !teamId) {
      return json({ ok: false, error: 'Crew is required for the crew/foreman role.' }, 400);
    }
    if (role === 'supervisor_cop' && !siteId) {
      return json({ ok: false, error: 'A site is required for Supervisor COP.' }, 400);
    }
    if (pin.length < 6) {
      return json({ ok: false, error: 'PIN must be at least 6 digits.' }, 400);
    }

    // ---- 3. Bikin akun Auth ----
    const email = `${nik}@sicatat.local`;
    const { data: createdAuth, error: createAuthErr } = await admin.auth.admin.createUser({
      email,
      password: pin,
      email_confirm: true,
    });
    if (createAuthErr) {
      const msg = /already been registered|already exists/i.test(createAuthErr.message)
        ? `NIK ${nik} is already registered.`
        : createAuthErr.message;
      return json({ ok: false, error: msg }, 400);
    }

    // ---- 4. Bikin baris profil app_user ----
    const { data: newProfile, error: insertErr } = await admin
      .from('app_user')
      .insert({ nik, name, role, team_id: teamId, site_id: siteId, phone, is_active: true })
      .select('id')
      .single();

    if (insertErr) {
      // Rollback -- jangan biarkan akun Auth yatim tanpa profil app_user.
      await admin.auth.admin.deleteUser(createdAuth.user.id);
      const msg = /duplicate key/i.test(insertErr.message)
        ? `NIK ${nik} is already registered.`
        : insertErr.message;
      return json({ ok: false, error: msg }, 400);
    }

    return json({ ok: true, id: newProfile.id });
  } catch (err) {
    return json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
  }
});
