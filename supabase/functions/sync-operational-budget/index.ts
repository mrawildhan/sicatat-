// Reads the approved Asam-Asam 2026 budget workbook and its two actual-cost
// extracts. Only USD transaction values are stored as the agreed display unit.

import { createClient } from "npm:@supabase/supabase-js@2";
import * as XLSX from "npm:xlsx@0.18.5";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const source = {
  budget: "https://drive.google.com/uc?export=download&id=1k6tmV5N60RBPnnpmTjSYN1VMQAlo14UX",
  cppActual: "https://drive.google.com/uc?export=download&id=1Mv8n8YmGAp4_XTr5V8OJVaUKRGZWeBc_",
  portActual: "https://drive.google.com/uc?export=download&id=16Gv5TC5Uri5MjDp8JWfLNryf4Bkksu3O",
} as const;

const sites = [
  { site: "CPP", budgetSheet: "3271 (Mtc)", actualUrl: source.cppActual },
  { site: "PORT", budgetSheet: "3275 (Mtc)", actualUrl: source.portActual },
] as const;

const periods = ["202601", "202602", "202603", "202604", "202605", "202606"] as const;
const budgetMonthLabels = ["JAN-26", "FEB-26", "MAR-26", "APR-26", "MAY-26", "JUN-26"] as const;

type SnapshotRow = {
  source_key: string;
  site_code: "CPP" | "PORT";
  period_start: string;
  budget_usd: number;
  actual_usd: number;
  source_fingerprint: string;
  synced_at: string;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function compact(value: unknown) {
  return String(value ?? "").trim();
}

function numberValue(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const raw = compact(value).replace(/[,$\s]/g, "");
  if (!raw || raw === "-" || raw.startsWith("#")) return 0;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : 0;
}

function headerIndex(row: unknown[]) {
  const result = new Map<string, number>();
  row.forEach((value, index) => result.set(compact(value).toUpperCase(), index));
  return result;
}

function findHeaderRow(values: unknown[][], required: string[]) {
  const index = values.findIndex((row) => {
    const headers = headerIndex(row);
    return required.every((name) => headers.has(name));
  });
  if (index < 0) throw new Error(`Kolom ${required.join(", ")} tidak ditemukan.`);
  return { index, headers: headerIndex(values[index]) };
}

function periodStart(period: string) {
  return `${period.slice(0, 4)}-${period.slice(4)}-01`;
}

async function download(url: string, label: string) {
  const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw new Error(`${label} tidak dapat dibaca (HTTP ${response.status}).`);
  return await response.arrayBuffer();
}

async function fingerprint(buffers: ArrayBuffer[]) {
  const size = buffers.reduce((total, buffer) => total + buffer.byteLength, 0);
  const data = new Uint8Array(size);
  let offset = 0;
  for (const buffer of buffers) {
    data.set(new Uint8Array(buffer), offset);
    offset += buffer.byteLength;
  }
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)]
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join("");
}

function budgetByPeriod(workbook: XLSX.WorkBook, sheetName: string) {
  const sheet = workbook.Sheets[sheetName];
  if (!sheet) throw new Error(`Workbook budget tidak memiliki sheet ${sheetName}.`);
  const values = XLSX.utils.sheet_to_json<unknown[]>(sheet, {
    header: 1,
    defval: "",
    raw: false,
  });
  // The workbook uses two header rows: “Expense” and the month labels are
  // above “Type” and “Description”. The two left columns are stable in both
  // approved maintenance sheets.
  const index = values.findIndex((row) => headerIndex(row).has("JAN-26"));
  if (index < 0) throw new Error(`Sheet ${sheetName} tidak memiliki kolom JAN-26.`);
  const headers = headerIndex(values[index]);
  const expenseColumn = 0;
  const descriptionColumn = 1;
  const months = new Map<string, number>();
  for (const period of periods) months.set(period, 0);
  for (const row of values.slice(index + 1)) {
    if (!compact(row[expenseColumn]) || !compact(row[descriptionColumn])) continue;
    for (let month = 0; month < periods.length; month += 1) {
      const column = headers.get(budgetMonthLabels[month]);
      if (column != null) {
        months.set(periods[month], (months.get(periods[month]) ?? 0) + numberValue(row[column]));
      }
    }
  }
  if ([...months.values()].every((value) => value === 0)) {
    throw new Error(`Sheet ${sheetName} tidak memiliki nilai budget Januari–Juni 2026.`);
  }
  return months;
}

function actualByPeriod(buffer: ArrayBuffer, site: string) {
  const workbook = XLSX.read(buffer, { type: "array", cellDates: false });
  const sheetName = workbook.SheetNames[0];
  if (!sheetName) throw new Error(`File aktual ${site} tidak memiliki sheet data.`);
  const values = XLSX.utils.sheet_to_json<unknown[]>(workbook.Sheets[sheetName], {
    header: 1,
    defval: "",
    raw: false,
  });
  const { index, headers } = findHeaderRow(values, ["FULL_PERIOD", "TRAN_AMOUNT"]);
  const periodColumn = headers.get("FULL_PERIOD")!;
  const amountColumn = headers.get("TRAN_AMOUNT")!;
  const months = new Map<string, number>();
  for (const period of periods) months.set(period, 0);
  for (const row of values.slice(index + 1)) {
    const period = compact(row[periodColumn]).replace(/\D/g, "").slice(0, 6);
    if (!months.has(period)) continue;
    months.set(period, (months.get(period) ?? 0) + numberValue(row[amountColumn]));
  }
  return months;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Metode tidak diizinkan." }, 405);
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ ok: false, error: "Sesi login diperlukan." }, 401);
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await callerClient.auth.getUser();
  if (authError || !user?.email) return json({ ok: false, error: "Sesi login tidak valid." }, 401);
  const admin = createClient(supabaseUrl, serviceRoleKey);
  const nik = user.email.replace("@sicatat.local", "");
  const { data: caller, error: callerError } = await admin
      .from("app_user")
      .select("id,is_active")
      .eq("nik", nik)
      .maybeSingle();
  if (callerError || !caller?.is_active) return json({ ok: false, error: "Akun tidak aktif." }, 403);

  try {
    const [budgetBuffer, cppBuffer, portBuffer] = await Promise.all([
      download(source.budget, "Workbook budget"),
      download(source.cppActual, "Aktual CPP"),
      download(source.portActual, "Aktual PORT"),
    ]);
    const sourceFingerprint = await fingerprint([budgetBuffer, cppBuffer, portBuffer]);
    const { data: previous } = await admin
        .from("operational_budget_sync_log")
        .select("source_fingerprint")
        .eq("status", "completed")
        .order("completed_at", { ascending: false })
        .limit(1)
        .maybeSingle();
    const now = new Date().toISOString();
    if (previous?.source_fingerprint === sourceFingerprint) {
      await admin.from("operational_budget_sync_log").insert({
        status: "completed",
        snapshot_rows: 0,
        source_fingerprint: sourceFingerprint,
        detail: "Tidak ada perubahan pada budget maupun aktual Asam-Asam.",
        triggered_by: caller.id,
      });
      return json({ ok: true, changed: false, rows: 0, synced_at: now });
    }

    const budgetWorkbook = XLSX.read(budgetBuffer, { type: "array", cellDates: false });
    const actualBuffers = new Map([["CPP", cppBuffer], ["PORT", portBuffer]]);
    const rows: SnapshotRow[] = [];
    for (const config of sites) {
      const budget = budgetByPeriod(budgetWorkbook, config.budgetSheet);
      const actual = actualByPeriod(actualBuffers.get(config.site)!, config.site);
      for (const period of periods) {
        rows.push({
          source_key: `${config.site}|${period}`,
          site_code: config.site,
          period_start: periodStart(period),
          budget_usd: budget.get(period) ?? 0,
          actual_usd: actual.get(period) ?? 0,
          source_fingerprint: sourceFingerprint,
          synced_at: now,
        });
      }
    }
    if (rows.length !== 12) throw new Error("Snapshot anggaran Asam-Asam tidak lengkap.");
    const { error: writeError } = await admin
        .from("operational_budget_month")
        .upsert(rows, { onConflict: "source_key" });
    if (writeError) throw writeError;
    const { error: deleteError } = await admin
        .from("operational_budget_month")
        .delete()
        .in("site_code", ["CPP", "PORT"])
        .neq("source_fingerprint", sourceFingerprint);
    if (deleteError) throw deleteError;
    await admin.from("operational_budget_sync_log").insert({
      status: "completed",
      snapshot_rows: rows.length,
      source_fingerprint: sourceFingerprint,
      detail: "Budget dan aktual USD Asam-Asam Januari–Juni 2026 tersimpan.",
      triggered_by: caller.id,
    });
    return json({ ok: true, changed: true, rows: rows.length, synced_at: now });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await admin.from("operational_budget_sync_log").insert({
      status: "failed",
      detail: message,
      triggered_by: caller.id,
    });
    return json({ ok: false, error: message }, 500);
  }
});
