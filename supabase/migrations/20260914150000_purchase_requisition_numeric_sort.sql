-- "No. PR terbaru" sorted no_pr as text, so "9876" ranked above "25557" and,
-- with the 60-row search limit, the newest PRs could fall off the list. The
-- source sheet mixes formats ("25557", "PR 002400", "PR15758", "18783/ 18784",
-- header rows such as "No Pr"), so sort on the first run of digits instead.
-- Rows without digits get NULL and are placed last by the app.

alter table public.purchase_requisition
  add column if not exists no_pr_number bigint
  generated always as (
    nullif(left(substring(no_pr from '[0-9]+'), 18), '')::bigint
  ) stored;

create index if not exists idx_purchase_requisition_no_pr_number
  on public.purchase_requisition (no_pr_number desc nulls last, no_pr);
