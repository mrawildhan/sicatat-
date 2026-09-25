-- Anggaran shows the full 2026 budget (owner choice 2026-09-25); actual months
-- fill in as the actual workbooks are updated. The monthly snapshot was
-- limited to January-June 2026.
alter table public.operational_budget_month
  drop constraint if exists operational_budget_month_period_start_check;

alter table public.operational_budget_month
  add constraint operational_budget_month_period_start_check
  check (period_start >= date '2026-01-01' and period_start <= date '2026-12-01');
