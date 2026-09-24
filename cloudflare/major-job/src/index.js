// SICATAT Major Job API (Cloudflare Worker).
//
// Admin-only. Every request carries the caller's Supabase access token, which
// is verified here against the project's public JWKS (ES256), and the caller
// must be an active SICATAT admin (`is_active_sicatat_admin` RPC, called with
// the caller's own token). No Supabase secret is stored in this Worker.
//
// Job rows live in D1 (binding DB); photo bytes live in KV (binding PHOTOS,
// key `photo:<id>`) because R2 is not enabled on the account.

export const MAX_PHOTOS_PER_JOB = 8;
export const MAX_PHOTO_BYTES = 2 * 1024 * 1024;
export const KV_CAPACITY_BYTES = 1024 * 1024 * 1024; // Workers KV free plan
const MAX_DESCRIPTION = 500;
const MAX_JSON_BYTES = 16 * 1024;
const ADMIN_CACHE_MS = 5 * 60 * 1000;
const JWKS_CACHE_MS = 10 * 60 * 1000;
const LOCAL_ORIGIN = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });

// ------------------------------------------------------------------ auth

function base64UrlToBytes(value) {
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, c => c.charCodeAt(0));
}

const decodeJsonPart = part =>
  JSON.parse(new TextDecoder().decode(base64UrlToBytes(part)));

let jwksCache = null;

async function loadJwks(env, force = false) {
  const url = `${env.SUPABASE_URL}/auth/v1/.well-known/jwks.json`;
  if (!force && jwksCache && jwksCache.url === url && jwksCache.expires > Date.now()) {
    return jwksCache.keys;
  }
  const response = await fetch(url);
  if (!response.ok) throw new HttpError(503, 'Kunci login tidak dapat diperiksa. Coba lagi.');
  const { keys } = await response.json();
  jwksCache = { url, keys: Array.isArray(keys) ? keys : [], expires: Date.now() + JWKS_CACHE_MS };
  return jwksCache.keys;
}

/** Verifies a Supabase access token and returns its claims. */
export async function verifySupabaseToken(token, env, now = Date.now()) {
  const invalid = () => new HttpError(401, 'Sesi login tidak valid. Silakan masuk kembali.');
  const parts = token.split('.');
  if (parts.length !== 3) throw invalid();
  let header;
  let claims;
  try {
    header = decodeJsonPart(parts[0]);
    claims = decodeJsonPart(parts[1]);
  } catch {
    throw invalid();
  }
  if (header.alg !== 'ES256' || typeof header.kid !== 'string') throw invalid();
  let jwk = (await loadJwks(env)).find(key => key.kid === header.kid);
  // A rotated signing key is not in the cached set yet.
  if (!jwk) jwk = (await loadJwks(env, true)).find(key => key.kid === header.kid);
  if (!jwk) throw invalid();
  const key = await crypto.subtle.importKey(
    'jwk',
    { kty: jwk.kty, crv: jwk.crv, x: jwk.x, y: jwk.y, ext: true },
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['verify'],
  );
  const valid = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    base64UrlToBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!valid) throw invalid();
  if (typeof claims.exp !== 'number' || claims.exp * 1000 <= now) {
    throw new HttpError(401, 'Sesi login sudah berakhir. Silakan masuk kembali.');
  }
  if (claims.iss !== `${env.SUPABASE_URL}/auth/v1` || claims.role !== 'authenticated' || typeof claims.sub !== 'string') {
    throw invalid();
  }
  return claims;
}

const adminCache = new Map();

async function isActiveAdmin(token, claims, env) {
  const cached = adminCache.get(claims.sub);
  if (cached && cached.expires > Date.now()) return cached.admin;
  const response = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/is_active_sicatat_admin`, {
    method: 'POST',
    headers: {
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    },
    body: '{}',
  });
  if (response.status === 401) throw new HttpError(401, 'Sesi login tidak valid. Silakan masuk kembali.');
  if (!response.ok) throw new HttpError(503, 'Hak akses tidak dapat diperiksa. Coba lagi.');
  const admin = (await response.json()) === true;
  adminCache.set(claims.sub, { admin, expires: Date.now() + ADMIN_CACHE_MS });
  return admin;
}

export async function authenticateAdmin(request, env) {
  const header = request.headers.get('authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!token) throw new HttpError(401, 'Silakan masuk ke SICATAT terlebih dahulu.');
  const claims = await verifySupabaseToken(token, env);
  if (!(await isActiveAdmin(token, claims, env))) {
    throw new HttpError(403, 'Major Job hanya untuk admin.');
  }
  const email = typeof claims.email === 'string' ? claims.email : '';
  return { id: claims.sub, nik: email.split('@')[0] || claims.sub };
}

// ------------------------------------------------------------------ images

/** Reads the real type and pixel size from JPEG/PNG bytes. */
export function imageInfo(bytes) {
  const u16 = i => (bytes[i] << 8) | bytes[i + 1];
  const u32 = i => ((bytes[i] << 24) >>> 0) + (bytes[i + 1] << 16) + (bytes[i + 2] << 8) + bytes[i + 3];
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length > 24 && png.every((b, i) => bytes[i] === b)) {
    return { mimeType: 'image/png', width: u32(16), height: u32(20) };
  }
  if (bytes.length > 4 && bytes[0] === 0xff && bytes[1] === 0xd8) {
    let i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] !== 0xff) return null;
      const marker = bytes[i + 1];
      if (marker === 0xff) {
        i += 1; // fill byte
        continue;
      }
      const isFrame =
        marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
      if (isFrame) return { mimeType: 'image/jpeg', width: u16(i + 7), height: u16(i + 5) };
      if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd9)) {
        i += 2;
        continue;
      }
      i += 2 + u16(i + 2);
    }
  }
  return null;
}

// ------------------------------------------------------------------ helpers

const MONTH = /^\d{4}-(0[1-9]|1[0-2])$/;

function validDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

function cleanDescription(value) {
  if (typeof value !== 'string') return null;
  const text = value.trim().replace(/\s+/g, ' ');
  return text.length >= 1 && text.length <= MAX_DESCRIPTION ? text : null;
}

async function readJson(request) {
  if (Number(request.headers.get('content-length')) > MAX_JSON_BYTES) {
    throw new HttpError(413, 'Data terlalu besar.');
  }
  try {
    return await request.json();
  } catch {
    throw new HttpError(400, 'Format data tidak valid.');
  }
}

const photoKey = id => `photo:${id}`;
const now = () => new Date().toISOString();

const photoView = row => ({
  id: row.id,
  position: row.position,
  mime_type: row.mime_type,
  width: row.width,
  height: row.height,
  size_bytes: row.size_bytes,
});

async function requireJob(env, id) {
  const job = await env.DB.prepare('SELECT * FROM job WHERE id = ?').bind(id).first();
  if (!job) throw new HttpError(404, 'Pekerjaan tidak ditemukan.');
  return job;
}

// ------------------------------------------------------------------ handlers

// Weeks run on across months (29 September – 05 Oktober), so the app asks for
// a date range; `month` remains for a plain calendar month.
const MAX_RANGE_DAYS = 62;

function listRange(url) {
  const month = url.searchParams.get('month');
  if (month !== null) {
    if (!MONTH.test(month)) throw new HttpError(400, 'Bulan harus berformat YYYY-MM.');
    return [`${month}-01`, `${month}-31`];
  }
  const from = url.searchParams.get('from');
  const to = url.searchParams.get('to');
  if (!validDate(from) || !validDate(to) || from > to) {
    throw new HttpError(400, 'Rentang tanggal harus from=YYYY-MM-DD&to=YYYY-MM-DD.');
  }
  if ((Date.parse(to) - Date.parse(from)) / 86400000 > MAX_RANGE_DAYS) {
    throw new HttpError(400, `Rentang tanggal maksimal ${MAX_RANGE_DAYS} hari.`);
  }
  return [from, to];
}

async function listJobs(env, url) {
  const [from, to] = listRange(url);
  const [jobs, photos] = await env.DB.batch([
    env.DB.prepare(
      'SELECT * FROM job WHERE work_date BETWEEN ? AND ? ORDER BY work_date, created_at',
    ).bind(from, to),
    env.DB.prepare(
      `SELECT p.* FROM photo p JOIN job j ON j.id = p.job_id
       WHERE j.work_date BETWEEN ? AND ? ORDER BY p.job_id, p.position`,
    ).bind(from, to),
  ]);
  const byJob = new Map();
  for (const photo of photos.results) {
    if (!byJob.has(photo.job_id)) byJob.set(photo.job_id, []);
    byJob.get(photo.job_id).push(photoView(photo));
  }
  return json({ jobs: jobs.results.map(job => ({ ...job, photos: byJob.get(job.id) ?? [] })) });
}

async function getJob(env, id) {
  const job = await requireJob(env, id);
  const { results } = await env.DB.prepare(
    'SELECT * FROM photo WHERE job_id = ? ORDER BY position',
  ).bind(id).all();
  return json({ job: { ...job, photos: results.map(photoView) } });
}

async function createJob(env, request, user) {
  const body = await readJson(request);
  const description = cleanDescription(body.description);
  if (!validDate(body.work_date)) throw new HttpError(400, 'Tanggal pekerjaan tidak valid.');
  if (!description) throw new HttpError(400, `Deskripsi wajib diisi (maks. ${MAX_DESCRIPTION} karakter).`);
  const id = crypto.randomUUID();
  const stamp = now();
  await env.DB.prepare(
    'INSERT INTO job (id, work_date, description, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
  ).bind(id, body.work_date, description, user.nik, stamp, stamp).run();
  return json({ job: { ...(await requireJob(env, id)), photos: [] } }, 201);
}

async function updateJob(env, request, id) {
  const body = await readJson(request);
  const sets = [];
  const values = [];
  if (body.work_date !== undefined) {
    if (!validDate(body.work_date)) throw new HttpError(400, 'Tanggal pekerjaan tidak valid.');
    sets.push('work_date = ?');
    values.push(body.work_date);
  }
  if (body.description !== undefined) {
    const description = cleanDescription(body.description);
    if (!description) throw new HttpError(400, `Deskripsi wajib diisi (maks. ${MAX_DESCRIPTION} karakter).`);
    sets.push('description = ?');
    values.push(description);
  }
  if (!sets.length) throw new HttpError(400, 'Tidak ada perubahan.');
  const result = await env.DB.prepare(
    `UPDATE job SET ${sets.join(', ')}, updated_at = ? WHERE id = ?`,
  ).bind(...values, now(), id).run();
  if (!result.meta.changes) throw new HttpError(404, 'Pekerjaan tidak ditemukan.');
  return json({ job: await requireJob(env, id) });
}

async function deleteJob(env, id) {
  const { results } = await env.DB.prepare('SELECT id FROM photo WHERE job_id = ?').bind(id).all();
  const [, deleted] = await env.DB.batch([
    env.DB.prepare('DELETE FROM photo WHERE job_id = ?').bind(id),
    env.DB.prepare('DELETE FROM job WHERE id = ?').bind(id),
  ]);
  if (!deleted.meta.changes) throw new HttpError(404, 'Pekerjaan tidak ditemukan.');
  await Promise.all(results.map(row => env.PHOTOS.delete(photoKey(row.id))));
  return json({ deleted: true });
}

async function uploadPhoto(env, request, jobId) {
  if (Number(request.headers.get('content-length')) > MAX_PHOTO_BYTES) {
    throw new HttpError(413, 'Foto terlalu besar (maks. 2 MB setelah dikompres).');
  }
  await requireJob(env, jobId);
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (!bytes.length) throw new HttpError(400, 'Foto kosong.');
  if (bytes.length > MAX_PHOTO_BYTES) throw new HttpError(413, 'Foto terlalu besar (maks. 2 MB setelah dikompres).');
  const info = imageInfo(bytes);
  if (!info || !info.width || !info.height) throw new HttpError(415, 'Foto harus berformat JPG atau PNG.');

  const id = crypto.randomUUID();
  await env.PHOTOS.put(photoKey(id), bytes, { metadata: { mimeType: info.mimeType } });
  let inserted;
  try {
    // Count and position are decided in the same statement, so two uploads at
    // once cannot push a job past the limit.
    inserted = await env.DB.prepare(
      `INSERT INTO photo (id, job_id, position, mime_type, width, height, size_bytes, created_at)
       SELECT ?, ?, COALESCE((SELECT MAX(position) FROM photo WHERE job_id = ?), 0) + 1, ?, ?, ?, ?, ?
       WHERE (SELECT COUNT(*) FROM photo WHERE job_id = ?) < ?`,
    ).bind(id, jobId, jobId, info.mimeType, info.width, info.height, bytes.length, now(), jobId, MAX_PHOTOS_PER_JOB).run();
  } catch (error) {
    await env.PHOTOS.delete(photoKey(id));
    throw error;
  }
  if (!inserted.meta.changes) {
    await env.PHOTOS.delete(photoKey(id));
    throw new HttpError(409, `Satu pekerjaan maksimal ${MAX_PHOTOS_PER_JOB} foto.`);
  }
  const row = await env.DB.prepare('SELECT * FROM photo WHERE id = ?').bind(id).first();
  return json({ photo: photoView(row) }, 201);
}

async function reorderPhotos(env, request, jobId) {
  const body = await readJson(request);
  const ids = body.ids;
  const { results } = await env.DB.prepare('SELECT id FROM photo WHERE job_id = ?').bind(jobId).all();
  const current = new Set(results.map(row => row.id));
  if (!Array.isArray(ids) || ids.length !== current.size || new Set(ids).size !== ids.length || !ids.every(id => current.has(id))) {
    throw new HttpError(400, 'Urutan foto tidak sesuai dengan foto pekerjaan ini.');
  }
  if (ids.length) {
    await env.DB.batch(ids.map((id, index) =>
      env.DB.prepare('UPDATE photo SET position = ? WHERE id = ?').bind(index + 1, id)));
  }
  return json({ ordered: ids.length });
}

async function getPhoto(env, id) {
  const row = await env.DB.prepare('SELECT mime_type FROM photo WHERE id = ?').bind(id).first();
  if (!row) throw new HttpError(404, 'Foto tidak ditemukan.');
  const bytes = await env.PHOTOS.get(photoKey(id), 'arrayBuffer');
  if (!bytes) throw new HttpError(404, 'File foto tidak ditemukan.');
  return new Response(bytes, {
    headers: {
      'content-type': row.mime_type,
      // Photo ids are never reused, so the bytes behind an id never change.
      'cache-control': 'private, max-age=31536000, immutable',
    },
  });
}

async function deletePhoto(env, id) {
  const result = await env.DB.prepare('DELETE FROM photo WHERE id = ?').bind(id).run();
  if (!result.meta.changes) throw new HttpError(404, 'Foto tidak ditemukan.');
  await env.PHOTOS.delete(photoKey(id));
  return json({ deleted: true });
}

async function usage(env) {
  const row = await env.DB.prepare(
    'SELECT COUNT(*) AS photos, COALESCE(SUM(size_bytes), 0) AS bytes FROM photo',
  ).first();
  return json({ photos: row.photos, bytes: row.bytes, capacity_bytes: KV_CAPACITY_BYTES });
}

async function route(request, env, user) {
  const url = new URL(request.url);
  const [resource, id, child, ...rest] = url.pathname.split('/').filter(Boolean).map(decodeURIComponent);
  const method = request.method;
  if (rest.length === 0) {
    if (resource === 'usage' && !id && method === 'GET') return usage(env);
    if (resource === 'jobs' && !id) {
      if (method === 'GET') return listJobs(env, url);
      if (method === 'POST') return createJob(env, request, user);
    }
    if (resource === 'jobs' && id && !child) {
      if (method === 'GET') return getJob(env, id);
      if (method === 'PATCH') return updateJob(env, request, id);
      if (method === 'DELETE') return deleteJob(env, id);
    }
    if (resource === 'jobs' && id && child === 'photos' && method === 'POST') return uploadPhoto(env, request, id);
    if (resource === 'jobs' && id && child === 'photo-order' && method === 'PUT') return reorderPhotos(env, request, id);
    if (resource === 'photos' && id && !child) {
      if (method === 'GET') return getPhoto(env, id);
      if (method === 'DELETE') return deletePhoto(env, id);
    }
  }
  throw new HttpError(404, 'Alamat tidak ditemukan.');
}

function corsHeaders(request, env) {
  const origin = request.headers.get('origin');
  const allowed = (env.ALLOWED_ORIGINS ?? '').split(',').map(value => value.trim()).filter(Boolean);
  if (!origin || !(allowed.includes(origin) || LOCAL_ORIGIN.test(origin))) return { vary: 'Origin' };
  return {
    'access-control-allow-origin': origin,
    'access-control-allow-methods': 'GET, POST, PATCH, PUT, DELETE, OPTIONS',
    'access-control-allow-headers': 'authorization, content-type',
    'access-control-max-age': '86400',
    vary: 'Origin',
  };
}

export function createWorker({ authenticate = authenticateAdmin } = {}) {
  return {
    async fetch(request, env) {
      const cors = corsHeaders(request, env);
      if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
      let response;
      try {
        const user = await authenticate(request, env);
        response = await route(request, env, user);
      } catch (error) {
        if (!(error instanceof HttpError)) console.error(error);
        response = error instanceof HttpError
          ? json({ error: error.message }, error.status)
          : json({ error: 'Terjadi kesalahan pada server Major Job.' }, 500);
      }
      for (const [name, value] of Object.entries(cors)) response.headers.set(name, value);
      return response;
    },
  };
}

export default createWorker();
