// Imports only the PR fields used by SICATAT. The original workbook stays in
// Google Drive; application searches read this compact Supabase snapshot.

import * as XLSX from "npm:xlsx@0.18.5";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const sourceWorkbookId = "1yIQHXe6YzMu7ymIvqUVRM2KNv0tWA93D";
const sourceUrl = `https://drive.usercontent.google.com/download?id=${sourceWorkbookId}&export=download&confirm=t`;

type RequisitionRow = {
  source_key: string;
  no_pr: string;
  no_po: string | null;
  description: string | null;
  equip_ref: string | null;
  closed_date: string | null;
  release_date: string | null;
  status: string | null;
  notes: string | null;
  source_fingerprint: string;
  synced_at: string;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  if (error && typeof error === "object") {
    const value = error as { message?: unknown; details?: unknown; hint?: unknown; code?: unknown };
    return String(value.message ?? value.details ?? value.hint ?? value.code ?? JSON.stringify(error));
  }
  return String(error);
}

function compact(value: unknown) {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}

function nullable(value: unknown) {
  const result = compact(value);
  return result || null;
}

function headerIndex(row: unknown[]) {
  const result = new Map<string, number>();
  row.forEach((value, index) => result.set(compact(value).toUpperCase(), index));
  return result;
}

function formatDate(year: number, month: number, day: number) {
  if (!year || !month || !day || year < 1900 || year > 2100) return null;
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  return date.toISOString().slice(0, 10);
}

function normalizeDate(value: unknown) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return formatDate(value.getUTCFullYear(), value.getUTCMonth() + 1, value.getUTCDate());
  }
  if (typeof value === "number") {
    // Excel's date serial starts from 30 December 1899 (including its legacy
    // 1900 leap-year offset).  Keeping this local avoids an optional SSF API
    // that is not exposed by every server-side xlsx build.
    const date = new Date(Date.UTC(1899, 11, 30) + Math.round(value * 86400000));
    return formatDate(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate());
  }
  const raw = compact(value);
  if (!raw) return null;
  const iso = raw.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$/);
  if (iso) return formatDate(Number(iso[1]), Number(iso[2]), Number(iso[3]));
  const dmy = raw.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$/);
  if (dmy) {
    const year = Number(dmy[3].length === 2 ? `20${dmy[3]}` : dmy[3]);
    return formatDate(year, Number(dmy[2]), Number(dmy[1]));
  }
  const parsed = Date.parse(raw);
  if (Number.isNaN(parsed)) return null;
  const date = new Date(parsed);
  return formatDate(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate());
}

async function fingerprint(bytes: ArrayBuffer) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function parseRows(bytes: ArrayBuffer, sourceFingerprint: string, syncedAt: string) {
  const workbook = XLSX.read(bytes, { type: "array", raw: true });
  const sheet = workbook.Sheets["Data PR"] ?? workbook.Sheets[workbook.SheetNames[0]];
  if (!sheet) throw new Error("Sheet Data PR tidak ditemukan.");
  const rows = XLSX.utils.sheet_to_json<unknown[]>(sheet, {
    header: 1,
    defval: "",
    raw: true,
  });
  const headerRow = rows.findIndex((row) => headerIndex(row).has("NO PR"));
  if (headerRow < 0) throw new Error("Kolom NO PR tidak ditemukan.");
  const headers = headerIndex(rows[headerRow]);
  const value = (row: unknown[], name: string) => row[headers.get(name) ?? -1];
  const result: RequisitionRow[] = [];
  rows.slice(headerRow + 1).forEach((row, offset) => {
    const noPr = compact(value(row, "NO PR")).replace(/^'+|'+$/g, "");
    const description = nullable(value(row, "DISCRIPTION"));
    if (!noPr && !description) return;
    if (!noPr) return;
    result.push({
      source_key: `pr-${headerRow + offset + 2}`,
      no_pr: noPr,
      no_po: nullable(value(row, "PO NO")),
      description,
      equip_ref: nullable(value(row, "EQUIP REF")),
      closed_date: normalizeDate(value(row, "CLOSED DATE")),
      release_date: normalizeDate(value(row, "RELEASE DATE")),
      status: nullable(value(row, "STATUS")),
      notes: nullable(value(row, "KETERANGAN")),
      source_fingerprint: sourceFingerprint,
      synced_at: syncedAt,
    });
  });
  return result;
}

async function upsertInBatches(
  admin: ReturnType<typeof createClient>,
  rows: RequisitionRow[],
) {
  for (let start = 0; start < rows.length; start += 500) {
    const { error } = await admin
      .from("purchase_requisition")
      .upsert(rows.slice(start, start + 500), { onConflict: "source_key" });
    if (error) throw error;
  }
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
    const response = await fetch(sourceUrl, { signal: AbortSignal.timeout(60000) });
    if (!response.ok) throw new Error(`File PR tidak dapat dibaca (HTTP ${response.status}).`);
    const bytes = await response.arrayBuffer();
    const sourceFingerprint = await fingerprint(bytes);
    const syncedAt = new Date().toISOString();
    const rows = parseRows(bytes, sourceFingerprint, syncedAt);
    if (rows.length === 0) throw new Error("Tidak ada data PR yang dapat diimpor.");
    await upsertInBatches(admin, rows);
    const { error: deleteError } = await admin
      .from("purchase_requisition")
      .delete()
      .neq("source_fingerprint", sourceFingerprint);
    if (deleteError) throw deleteError;
    await admin.from("purchase_requisition_sync_log").insert({
      status: "completed",
      snapshot_rows: rows.length,
      source_fingerprint: sourceFingerprint,
      detail: "Snapshot Data PR dari spreadsheet PR.xlsx berhasil diperbarui.",
      triggered_by: caller.id,
    });
    return json({ ok: true, rows: rows.length, synced_at: syncedAt });
  } catch (error) {
    const message = errorMessage(error);
    await admin.from("purchase_requisition_sync_log").insert({
      status: "failed",
      detail: message,
      triggered_by: caller.id,
    });
    // The client presents this operational error beside the retry button.  A
    // normal JSON response keeps the source problem understandable instead of
    // collapsing it into a generic FunctionsHttpException.
    return json({ ok: false, error: message });
  }
});
