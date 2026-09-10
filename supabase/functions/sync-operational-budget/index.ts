// Imports only the compact Google Sheets CSV views. The source workbooks stay
// in Drive; Supabase stores a small, searchable snapshot for the application.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const workbookId = "1k6tmV5N60RBPnnpmTjSYN1VMQAlo14UX";
const source = {
  cppBudget: `https://docs.google.com/spreadsheets/d/${workbookId}/gviz/tq?tqx=out:csv&sheet=3271%20(Mtc)`,
  portBudget: `https://docs.google.com/spreadsheets/d/${workbookId}/gviz/tq?tqx=out:csv&sheet=3275%20(Mtc)`,
  cppActual: "https://docs.google.com/spreadsheets/d/1Mv8n8YmGAp4_XTr5V8OJVaUKRGZWeBc_/gviz/tq?tqx=out:csv&gid=1764239569",
  portActual: "https://docs.google.com/spreadsheets/d/16Gv5TC5Uri5MjDp8JWfLNryf4Bkksu3O/gviz/tq?tqx=out:csv&gid=12963677",
} as const;

const sites = [
  { site: "CPP", budgetUrl: source.cppBudget, actualUrl: source.cppActual },
  { site: "PORT", budgetUrl: source.portBudget, actualUrl: source.portActual },
] as const;
const periods = ["202601", "202602", "202603", "202604", "202605", "202606"] as const;
const budgetMonthLabels = ["JAN-26", "FEB-26", "MAR-26", "APR-26", "MAY-26", "JUN-26"] as const;
type Site = (typeof sites)[number]["site"];
type CsvRows = string[][];

type BudgetItem = {
  source_key: string;
  site_code: Site;
  account_code: string;
  description: string;
  budget_usd: number;
  actual_usd: number;
  budget_months: Record<string, number>;
  actual_months: Record<string, number>;
  peak_period: string | null;
  peak_actual_usd: number;
  largest_transaction_usd: number;
  largest_transaction_date: string | null;
  largest_transaction_no: string | null;
  source_fingerprint: string;
  synced_at: string;
};

type SummaryRow = {
  source_key: string;
  site_code: Site;
  period_start: string;
  budget_usd: number;
  actual_usd: number;
  source_fingerprint: string;
  synced_at: string;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function compact(value: unknown) {
  return String(value ?? "").trim();
}

function numberValue(value: unknown) {
  const raw = compact(value).replace(/[,$\s]/g, "");
  if (!raw || raw === "-" || raw.startsWith("#")) return 0;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : 0;
}

function periodStart(period: string) {
  return `${period.slice(0, 4)}-${period.slice(4)}-01`;
}

function parseCsv(sourceText: string): CsvRows {
  const rows: CsvRows = [];
  let row: string[] = [];
  let value = "";
  let quoted = false;
  for (let index = 0; index < sourceText.length; index += 1) {
    const char = sourceText[index];
    if (char === '"') {
      if (quoted && sourceText[index + 1] === '"') {
        value += '"';
        index += 1;
      } else quoted = !quoted;
    } else if (char === "," && !quoted) {
      row.push(value);
      value = "";
    } else if ((char === "\n" || char === "\r") && !quoted) {
      if (char === "\r" && sourceText[index + 1] === "\n") index += 1;
      row.push(value);
      if (row.some((cell) => cell.length > 0)) rows.push(row);
      row = [];
      value = "";
    } else value += char;
  }
  row.push(value);
  if (row.some((cell) => cell.length > 0)) rows.push(row);
  return rows;
}

function headerIndex(row: string[]) {
  const result = new Map<string, number>();
  row.forEach((value, index) => result.set(compact(value).toUpperCase(), index));
  return result;
}

async function downloadCsv(url: string, label: string) {
  const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw new Error(`${label} tidak dapat dibaca (HTTP ${response.status}).`);
  return await response.text();
}

async function fingerprint(values: string[]) {
  const encoded = new TextEncoder().encode(values.join("\n--SICATAT-SOURCE--\n"));
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function budgetItems(rows: CsvRows, site: Site) {
  const headerRow = rows.findIndex((row) => compact(row[1]).toUpperCase() === "EXPENSE" && compact(row[2]).toUpperCase() === "EXPENSE");
  if (headerRow < 0) throw new Error(`Header budget ${site} tidak ditemukan.`);
  const headers = headerIndex(rows[headerRow]);
  const result = new Map<string, { description: string; months: Record<string, number> }>();
  for (const row of rows.slice(headerRow + 2)) {
    const code = compact(row[1]);
    const description = compact(row[2]);
    if (!code || !description) continue;
    const months: Record<string, number> = {};
    for (let month = 0; month < periods.length; month += 1) {
      months[periods[month]] = numberValue(row[headers.get(budgetMonthLabels[month]) ?? -1]);
    }
    result.set(code, { description, months });
  }
  return result;
}

function actualItems(rows: CsvRows) {
  const headerRow = rows.findIndex((row) => {
    const headers = headerIndex(row);
    return headers.has("ACCOUNT_CODE") && headers.has("FULL_PERIOD");
  });
  if (headerRow < 0) throw new Error("Header aktual tidak ditemukan.");
  const headers = headerIndex(rows[headerRow]);
  const accountColumn = headers.get("ACCOUNT_CODE")!;
  const periodColumn = headers.get("FULL_PERIOD")!;
  const amountColumn = (headers.get("TRANS_NO") ?? 14) + 1;
  const dateColumn = headers.get("PROCESS_DATE")!;
  const transactionColumn = headers.get("TRANSACTION_NO")!;
  const result = new Map<string, { months: Record<string, number>; largest: { amount: number; date: string | null; number: string | null } }>();
  for (const row of rows.slice(headerRow + 1)) {
    const period = compact(row[periodColumn]);
    if (!periods.includes(period as (typeof periods)[number])) continue;
    const code = compact(row[accountColumn]).slice(-5);
    if (!code) continue;
    const amount = numberValue(row[amountColumn]);
    const current = result.get(code) ?? { months: Object.fromEntries(periods.map((key) => [key, 0])), largest: { amount: 0, date: null, number: null } };
    current.months[period] += amount;
    if (amount > current.largest.amount) current.largest = { amount, date: compact(row[dateColumn]) || null, number: compact(row[transactionColumn]) || null };
    result.set(code, current);
  }
  return result;
}

function buildRows(site: Site, budgetCsv: string, actualCsv: string, sourceFingerprint: string, now: string) {
  const budget = budgetItems(parseCsv(budgetCsv), site);
  const actual = actualItems(parseCsv(actualCsv));
  const items: BudgetItem[] = [];
  for (const [code, budgetItem] of budget.entries()) {
    const actualItem = actual.get(code);
    const actualMonths = actualItem?.months ?? Object.fromEntries(periods.map((key) => [key, 0]));
    const budgetUsd = Object.values(budgetItem.months).reduce((total, value) => total + value, 0);
    const actualUsd = Object.values(actualMonths).reduce((total, value) => total + value, 0);
    const peakPeriod = periods.reduce((best, period) => actualMonths[period] > actualMonths[best] ? period : best, periods[0]);
    items.push({
      source_key: `${site}|${code}`, site_code: site, account_code: code, description: budgetItem.description,
      budget_usd: budgetUsd, actual_usd: actualUsd, budget_months: budgetItem.months, actual_months: actualMonths,
      peak_period: actualUsd > 0 ? peakPeriod : null, peak_actual_usd: actualMonths[peakPeriod],
      largest_transaction_usd: actualItem?.largest.amount ?? 0, largest_transaction_date: actualItem?.largest.date ?? null,
      largest_transaction_no: actualItem?.largest.number ?? null, source_fingerprint: sourceFingerprint, synced_at: now,
    });
  }
  const months: SummaryRow[] = periods.map((period) => ({
    source_key: `${site}|${period}`, site_code: site, period_start: periodStart(period),
    budget_usd: items.reduce((total, item) => total + item.budget_months[period], 0),
    actual_usd: items.reduce((total, item) => total + item.actual_months[period], 0),
    source_fingerprint: sourceFingerprint, synced_at: now,
  }));
  return { items, months };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Metode tidak diizinkan." }, 405);
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ ok: false, error: "Sesi login diperlukan." }, 401);
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const callerClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: authError } = await callerClient.auth.getUser();
  if (authError || !user?.email) return json({ ok: false, error: "Sesi login tidak valid." }, 401);
  const admin = createClient(supabaseUrl, serviceRoleKey);
  const nik = user.email.replace("@sicatat.local", "");
  const { data: caller, error: callerError } = await admin.from("app_user").select("id,is_active").eq("nik", nik).maybeSingle();
  if (callerError || !caller?.is_active) return json({ ok: false, error: "Akun tidak aktif." }, 403);

  try {
    const [cppBudget, portBudget, cppActual, portActual] = await Promise.all([
      downloadCsv(source.cppBudget, "Budget CPP"), downloadCsv(source.portBudget, "Budget PORT"),
      downloadCsv(source.cppActual, "Aktual CPP"), downloadCsv(source.portActual, "Aktual PORT"),
    ]);
    const sourceFingerprint = await fingerprint([cppBudget, portBudget, cppActual, portActual]);
    const now = new Date().toISOString();
    const cpp = buildRows("CPP", cppBudget, cppActual, sourceFingerprint, now);
    const port = buildRows("PORT", portBudget, portActual, sourceFingerprint, now);
    const items = [...cpp.items, ...port.items];
    const months = [...cpp.months, ...port.months];
    if (items.length === 0 || months.length !== 12) throw new Error("Snapshot anggaran Asam-Asam tidak lengkap.");
    const { error: itemError } = await admin.from("operational_budget_item").upsert(items, { onConflict: "source_key" });
    if (itemError) throw itemError;
    const { error: monthError } = await admin.from("operational_budget_month").upsert(months, { onConflict: "source_key" });
    if (monthError) throw monthError;
    await admin.from("operational_budget_item").delete().in("site_code", ["CPP", "PORT"]).neq("source_fingerprint", sourceFingerprint);
    await admin.from("operational_budget_month").delete().in("site_code", ["CPP", "PORT"]).neq("source_fingerprint", sourceFingerprint);
    await admin.from("operational_budget_sync_log").insert({
      status: "completed", snapshot_rows: items.length + months.length, source_fingerprint: sourceFingerprint,
      detail: "Ringkasan item budget dan aktual USD Asam-Asam Januari–Juni 2026 tersimpan.", triggered_by: caller.id,
    });
    return json({ ok: true, changed: true, rows: items.length + months.length, synced_at: now });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await admin.from("operational_budget_sync_log").insert({ status: "failed", detail: message, triggered_by: caller.id });
    return json({ ok: false, error: message }, 500);
  }
});
