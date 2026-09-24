# SICATAT Major Job API

Cloudflare Worker behind the admin-only **Major Job** menu (Operasional →
Major Job, `/major-job`): the owner's weekly/monthly photo report of
maintenance work. Data is deliberately **not** in Supabase (free-plan storage).

- **D1** `sicatat-major-job` (binding `DB`): tables `job` and `photo`
  (metadata only). Schema: `schema.sql`.
- **KV** `sicatat-major-job-photos` (binding `PHOTOS`): photo bytes under
  `photo:<id>`. R2 is not enabled on the account (it needs a card in the
  dashboard), so the owner chose KV: 1 GB free, 1000 writes/day. Photos are
  compressed in the app to ≤1200 px / ~200 KB first, and the Major Job screen
  shows usage against 1 GB.
- **Auth:** the app sends the user's Supabase access token. The Worker verifies
  it against the project's public JWKS (ES256) and calls the existing
  `is_active_sicatat_admin` RPC with the caller's own token. No Supabase secret
  is stored here; `SUPABASE_PUBLISHABLE_KEY` is the public key already in the app.
- CORS: `ALLOWED_ORIGINS` plus `http://localhost:*` for `flutter run -d chrome`.

## API

| Method | Path | |
|---|---|---|
| GET | `/jobs?month=YYYY-MM` | jobs of a month with their photos |
| POST | `/jobs` | `{work_date, description}` |
| GET / PATCH / DELETE | `/jobs/:id` | delete also removes its KV photos |
| POST | `/jobs/:id/photos` | raw JPEG/PNG body; type and size read from the bytes; max 8 per job |
| PUT | `/jobs/:id/photo-order` | `{ids: [...]}` (all photo ids of the job) |
| GET / DELETE | `/photos/:id` | |
| GET | `/usage` | photo count and bytes vs 1 GB |

## Deploy

```powershell
npx wrangler d1 execute sicatat-major-job --remote --file cloudflare/major-job/schema.sql --config cloudflare/major-job/wrangler.jsonc
npx wrangler deploy --config cloudflare/major-job/wrangler.jsonc
```

URL: `https://sicatat-major-job.sicatat.workers.dev` (`AppConfig.majorJobApiUrl`).

## Tests

`node --test cloudflare/major-job/test.mjs` (Node 22.5+). D1 is stood in by
`node:sqlite`, so the real SQL runs; the auth test signs ES256 tokens and
checks expired, forged, and non-admin tokens are rejected.
