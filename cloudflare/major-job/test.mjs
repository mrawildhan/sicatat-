import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { webcrypto } from 'node:crypto';
import worker, { createWorker, imageInfo, MAX_PHOTOS_PER_JOB } from './src/index.js';

const schema = readFileSync(new URL('./schema.sql', import.meta.url), 'utf8');

// D1 stand-in on node:sqlite so the Worker's real SQL runs in tests.
function fakeD1() {
  const db = new DatabaseSync(':memory:');
  db.exec(schema);
  const statement = (sql, params = []) => ({
    bind: (...values) => statement(sql, values),
    all: async () => ({ results: db.prepare(sql).all(...params) }),
    first: async () => db.prepare(sql).get(...params) ?? null,
    run: async () => ({ meta: { changes: Number(db.prepare(sql).run(...params).changes) } }),
    execute: () => /^\s*select/i.test(sql)
      ? { results: db.prepare(sql).all(...params) }
      : { results: [], meta: { changes: Number(db.prepare(sql).run(...params).changes) } },
  });
  return {
    prepare: sql => statement(sql),
    async batch(statements) {
      db.exec('BEGIN');
      try {
        const results = statements.map(s => s.execute());
        db.exec('COMMIT');
        return results;
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
    },
  };
}

function fakeKv() {
  const store = new Map();
  return {
    store,
    put: async (key, bytes) => void store.set(key, Uint8Array.from(bytes)),
    get: async key => (store.has(key) ? store.get(key).slice().buffer : null),
    delete: async key => void store.delete(key),
  };
}

const jpeg = (width, height) => Uint8Array.from([
  0xff, 0xd8,
  0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
  0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 0xff, width >> 8, width & 0xff, 0x03,
  0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xff, 0xd9,
]);

const env = () => ({
  DB: fakeD1(),
  PHOTOS: fakeKv(),
  ALLOWED_ORIGINS: 'https://sicatat.com',
  SUPABASE_URL: 'https://proj.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test',
});

const admin = createWorker({ authenticate: async () => ({ id: 'u1', nik: '12345' }) });
const call = (e, method, path, body, headers = {}) => admin.fetch(
  new Request(`https://api.test${path}`, {
    method,
    headers: body instanceof Uint8Array ? { 'content-type': 'image/jpeg', ...headers } : { 'content-type': 'application/json', ...headers },
    body: body === undefined ? undefined : body instanceof Uint8Array ? body : JSON.stringify(body),
  }),
  e,
);

test('ukuran foto dibaca dari isi file, bukan dari nama', () => {
  assert.deepEqual(imageInfo(jpeg(4000, 3000)), { mimeType: 'image/jpeg', width: 4000, height: 3000 });
  const png = new Uint8Array(33);
  png.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  png.set([0, 0, 0x04, 0x38, 0, 0, 0x07, 0x80], 16);
  assert.deepEqual(imageInfo(png), { mimeType: 'image/png', width: 1080, height: 1920 });
  assert.equal(imageInfo(new TextEncoder().encode('bukan gambar sama sekali')), null);
});

test('alur pekerjaan: buat, unggah, urutkan, daftar, hapus', async () => {
  const e = env();
  assert.equal((await call(e, 'POST', '/jobs', { work_date: '2026-02-30', description: 'x' })).status, 400);
  assert.equal((await call(e, 'POST', '/jobs', { work_date: '2026-08-04', description: '   ' })).status, 400);

  const created = await call(e, 'POST', '/jobs', { work_date: '2026-08-04', description: '  Fabrikasi   lower chute ' });
  assert.equal(created.status, 201);
  const { job } = await created.json();
  assert.equal(job.description, 'Fabrikasi lower chute');
  assert.equal(job.created_by, '12345');

  const first = await (await call(e, 'POST', `/jobs/${job.id}/photos`, jpeg(1280, 960))).json();
  const second = await (await call(e, 'POST', `/jobs/${job.id}/photos`, jpeg(720, 1280))).json();
  assert.equal(first.photo.position, 1);
  assert.equal(second.photo.width, 720);
  assert.equal((await call(e, 'POST', `/jobs/${job.id}/photos`, new TextEncoder().encode('teks'))).status, 415);

  assert.equal((await call(e, 'PUT', `/jobs/${job.id}/photo-order`, { ids: [first.photo.id] })).status, 400);
  assert.equal((await call(e, 'PUT', `/jobs/${job.id}/photo-order`, { ids: [second.photo.id, first.photo.id] })).status, 200);

  await call(e, 'POST', '/jobs', { work_date: '2026-09-01', description: 'Bulan lain' });
  const list = await (await call(e, 'GET', '/jobs?month=2026-08')).json();
  assert.equal(list.jobs.length, 1);
  assert.deepEqual(list.jobs[0].photos.map(p => p.id), [second.photo.id, first.photo.id]);
  assert.equal((await call(e, 'GET', '/jobs?month=2026-8')).status, 400);

  // Weeks cross months: 29 September – 05 Oktober is one range request.
  const range = await (await call(e, 'GET', '/jobs?from=2026-08-04&to=2026-09-01')).json();
  assert.deepEqual(range.jobs.map(j => j.description), ['Fabrikasi lower chute', 'Bulan lain']);
  assert.equal((await call(e, 'GET', '/jobs?from=2026-09-05&to=2026-09-01')).status, 400);
  assert.equal((await call(e, 'GET', '/jobs?from=2026-01-01&to=2026-06-01')).status, 400);
  assert.equal((await call(e, 'GET', '/jobs?from=2026-09-31&to=2026-10-05')).status, 400);

  const single = await (await call(e, 'GET', `/jobs/${job.id}`)).json();
  assert.deepEqual(single.job.photos.map(p => p.position), [1, 2]);
  assert.equal(single.job.photos[0].id, second.photo.id);
  assert.equal((await call(e, 'GET', '/jobs/tidak-ada')).status, 404);

  const image = await call(e, 'GET', `/photos/${first.photo.id}`);
  assert.equal(image.headers.get('content-type'), 'image/jpeg');
  assert.deepEqual(new Uint8Array(await image.arrayBuffer()), jpeg(1280, 960));

  const usage = await (await call(e, 'GET', '/usage')).json();
  assert.equal(usage.photos, 2);

  const patched = await (await call(e, 'PATCH', `/jobs/${job.id}`, { work_date: '2026-08-05' })).json();
  assert.equal(patched.job.work_date, '2026-08-05');

  assert.equal(e.PHOTOS.store.size, 2);
  assert.equal((await call(e, 'DELETE', `/jobs/${job.id}`)).status, 200);
  assert.equal(e.PHOTOS.store.size, 0, 'foto di KV ikut terhapus');
  assert.equal((await call(e, 'DELETE', `/jobs/${job.id}`)).status, 404);
});

test(`satu pekerjaan maksimal ${MAX_PHOTOS_PER_JOB} foto dan KV tidak menyisakan file`, async () => {
  const e = env();
  const { job } = await (await call(e, 'POST', '/jobs', { work_date: '2026-08-10', description: 'Banyak foto' })).json();
  for (let i = 0; i < MAX_PHOTOS_PER_JOB; i++) {
    assert.equal((await call(e, 'POST', `/jobs/${job.id}/photos`, jpeg(800, 600))).status, 201);
  }
  assert.equal((await call(e, 'POST', `/jobs/${job.id}/photos`, jpeg(800, 600))).status, 409);
  assert.equal(e.PHOTOS.store.size, MAX_PHOTOS_PER_JOB);
});

test('CORS hanya untuk sicatat.com dan localhost', async () => {
  const e = env();
  const preflight = await admin.fetch(new Request('https://api.test/jobs', { method: 'OPTIONS', headers: { origin: 'https://sicatat.com' } }), e);
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('access-control-allow-origin'), 'https://sicatat.com');
  const local = await call(e, 'GET', '/usage', undefined, { origin: 'http://localhost:5555' });
  assert.equal(local.headers.get('access-control-allow-origin'), 'http://localhost:5555');
  const other = await call(e, 'GET', '/usage', undefined, { origin: 'https://evil.example' });
  assert.equal(other.headers.get('access-control-allow-origin'), null);
});

// ------------------------------------------------------------ real auth path

const b64url = bytes => Buffer.from(bytes).toString('base64url');

async function signedToken(privateKey, kid, claims) {
  const head = b64url(JSON.stringify({ alg: 'ES256', kid, typ: 'JWT' }));
  const body = b64url(JSON.stringify(claims));
  const signature = await webcrypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, privateKey, new TextEncoder().encode(`${head}.${body}`));
  return `${head}.${body}.${b64url(new Uint8Array(signature))}`;
}

test('token Supabase diverifikasi dan hanya admin aktif yang boleh masuk', async t => {
  const e = env();
  const pair = await webcrypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const publicJwk = { ...(await webcrypto.subtle.exportKey('jwk', pair.publicKey)), kid: 'kunci-1', alg: 'ES256' };
  const stranger = await webcrypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const claims = (sub, exp = Math.floor(Date.now() / 1000) + 3600) => ({
    sub, exp, role: 'authenticated', iss: `${e.SUPABASE_URL}/auth/v1`, email: '777@sicatat.local',
  });
  const admins = new Set(['admin-1']);
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async (url, init = {}) => {
    if (String(url).endsWith('/jwks.json')) return Response.json({ keys: [publicJwk] });
    if (String(url).endsWith('/rpc/is_active_sicatat_admin')) {
      assert.equal(init.headers.apikey, 'sb_publishable_test');
      const sub = JSON.parse(Buffer.from(init.headers.authorization.split('.')[1], 'base64url')).sub;
      return Response.json(admins.has(sub));
    }
    throw new Error(`fetch tak terduga: ${url}`);
  };
  const request = token => worker.fetch(new Request('https://api.test/usage', token ? { headers: { authorization: `Bearer ${token}` } } : {}), e);

  assert.equal((await request()).status, 401);
  assert.equal((await request(await signedToken(pair.privateKey, 'kunci-1', claims('admin-1')))).status, 200);
  assert.equal((await request(await signedToken(pair.privateKey, 'kunci-1', claims('crew-1')))).status, 403);
  assert.equal((await request(await signedToken(pair.privateKey, 'kunci-1', claims('admin-1', 1000)))).status, 401, 'kedaluwarsa');
  assert.equal((await request(await signedToken(stranger.privateKey, 'kunci-1', claims('admin-1')))).status, 401, 'tanda tangan palsu');
  const genuine = await signedToken(pair.privateKey, 'kunci-1', claims('admin-1'));
  const [h, , s] = genuine.split('.');
  const forged = `${h}.${b64url(JSON.stringify(claims('crew-2')))}.${s}`;
  assert.equal((await request(forged)).status, 401, 'isi token diubah');
});
