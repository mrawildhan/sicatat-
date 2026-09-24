-- SICATAT Major Job (Cloudflare D1). Photo bytes live in the KV namespace
-- bound as PHOTOS under the key `photo:<id>`; this database keeps only
-- metadata. Apply with:
--   npx wrangler d1 execute sicatat-major-job --remote --file cloudflare/major-job/schema.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS job (
  id TEXT PRIMARY KEY,
  work_date TEXT NOT NULL
    CHECK (work_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  description TEXT NOT NULL
    CHECK (length(trim(description)) BETWEEN 1 AND 500),
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS job_work_date ON job (work_date, created_at);

CREATE TABLE IF NOT EXISTS photo (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL REFERENCES job (id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  mime_type TEXT NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png')),
  width INTEGER NOT NULL CHECK (width > 0),
  height INTEGER NOT NULL CHECK (height > 0),
  size_bytes INTEGER NOT NULL CHECK (size_bytes > 0),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS photo_job ON photo (job_id, position);
