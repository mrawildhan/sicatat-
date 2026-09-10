-- Approved Asam-Asam maintenance snapshot from the supplied budget workbook
-- and CPP/PORT actual-cost spreadsheets. Values are USD, January–June 2026.

insert into public.operational_budget_month (
  source_key,
  site_code,
  period_start,
  budget_usd,
  actual_usd,
  source_fingerprint,
  synced_at
) values
  ('CPP|202601', 'CPP', date '2026-01-01', 66880.00, 59686.22, 'asm-budget-approved-2026-09-10', timestamptz '2026-09-10 00:00:00+00'),
  ('CPP|202602', 'CPP', date '2026-02-01', 17380.00, 86854.99, 'asm-budget-approved-2026-09-10', timestamptz '2026-09-10 00:00:00+00'),
  ('CPP|202603', 'CPP', date '2026-03-01', 17630.00, 13503.99, 'asm-budget-approved-2026-09-10', timestamptz '2026-09-10 00:00:00+00'),
  ('CPP|202604', 'CPP', date '2026-04-01', 17380.00, 16726.25, 'asm-budget-approved-2026-09-10', timestamptz '2026-09-10 00:00:00+00'),
  ('CPP|202605', 'CPP', date '2026-05-01', 17630.00, 9801.43, 'asm-budget-approved-2026-09-10', timestamptz '2026-09-10 00:00:00+00'),
  ('CPP|202606', 'CPP', date '2026-06-01', 49812.00, 16393.42, 'asm-budget-approved-2026-09-10', timestamptz '2026-09-10 00:00:00+00'),
  ('PORT|202601', 'PORT', date '2026-01-01', 32830.00, 3169.99, 'asm-budget-approved-2026-09-10', timestamptz '2026-09-10 00:00:00+00'),
  ('PORT|202602', 'PORT', date '2026-02-01', 16830.00, 4927.86, 'asm-budget-approved-2026-09-10', timestamptz '2026-09-10 00:00:00+00'),
  ('PORT|202603', 'PORT', date '2026-03-01', 16830.00, 6067.35, 'asm-budget-approved-2026-09-10', timestamptz '2026-09-10 00:00:00+00'),
  ('PORT|202604', 'PORT', date '2026-04-01', 67380.00, 26177.67, 'asm-budget-approved-2026-09-10', timestamptz '2026-09-10 00:00:00+00'),
  ('PORT|202605', 'PORT', date '2026-05-01', 34130.00, 5763.49, 'asm-budget-approved-2026-09-10', timestamptz '2026-09-10 00:00:00+00'),
  ('PORT|202606', 'PORT', date '2026-06-01', 17830.00, 49606.70, 'asm-budget-approved-2026-09-10', timestamptz '2026-09-10 00:00:00+00')
on conflict (source_key) do update set
  budget_usd = excluded.budget_usd,
  actual_usd = excluded.actual_usd,
  source_fingerprint = excluded.source_fingerprint,
  synced_at = excluded.synced_at;
