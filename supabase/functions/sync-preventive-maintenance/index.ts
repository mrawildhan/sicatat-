// Synchronises the approved PM work-order files into a private database snapshot.
// The Flutter app never downloads or parses spreadsheets directly.

import { createClient } from "npm:@supabase/supabase-js@2";
import * as XLSX from "npm:xlsx@0.18.5";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const sources = [
  {
    site: "CPP",
    label: "CPP PM.xlsx",
    url: "https://drive.google.com/uc?export=download&id=1fzmWPxRiqH6ZIAECjqXN1PQJ99JkICEz",
  },
  {
    site: "PORT",
    label: "PORT PM.xlsx",
    url: "https://drive.google.com/uc?export=download&id=1lj-70kgos3_cSMQ6d7Ye8qjtAIA9N0LG",
  },
] as const;

type Row = {
  source_key: string;
  work_order: string;
  work_order_description: string;
  equipment_reference: string;
  crew_code: string;
  site_code: string;
  status_code: string;
  raised_on: string | null;
  planned_start_on: string | null;
  assigned_to: string | null;
  assigned_to_description: string | null;
  priority: string | null;
  priority_description: string | null;
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

function optional(value: unknown) {
  const result = compact(value);
  return result || null;
}

function dateValue(value: unknown) {
  const raw = compact(value);
  if (!raw) return null;
  const iso = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(raw);
  if (iso) {
    return [iso[1], iso[2].padStart(2, "0"), iso[3].padStart(2, "0")].join("-");
  }
  const dmy = /^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$/.exec(raw);
  if (!dmy) return null;
  const year = dmy[3].length === 2 ? 2000 + Number(dmy[3]) : Number(dmy[3]);
  // The PM export uses day/month/year when rendered as a localized date.
  return [String(year).padStart(4, "0"), dmy[2].padStart(2, "0"), dmy[1].padStart(2, "0")].join("-");
}

function headerIndex(header: unknown[]) {
  const result = new Map<string, number>();
  header.forEach((value, index) => result.set(compact(value).toUpperCase(), index));
  return result;
}

function valueAt(row: unknown[], headers: Map<string, number>, name: string) {
  return row[headers.get(name) ?? -1];
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

async function readSource(source: typeof sources[number]) {
  const response = await fetch(source.url, { signal: AbortSignal.timeout(20000) });
  if (!response.ok) throw new Error(`${source.label} tidak dapat dibaca (HTTP ${response.status}).`);
  const buffer = await response.arrayBuffer();
  const workbook = XLSX.read(buffer, { type: "array", cellDates: false });
  const sheetName = workbook.SheetNames[0];
  if (!sheetName) throw new Error(`${source.label} tidak memiliki sheet data.`);
  const sheet = workbook.Sheets[sheetName];
  const values = XLSX.utils.sheet_to_json<unknown[]>(sheet, {
    header: 1,
    defval: "",
    raw: false,
  });
  if (values.length < 2) throw new Error(`${source.label} tidak memiliki baris PM.`);
  const headers = headerIndex(values[0]);
  const required = ["WORK ORDER", "WORK ORDER DESC", "EQUIP REF", "CREW", "STATUS"];
  const missing = required.filter((name) => !headers.has(name));
  if (missing.length > 0) {
    throw new Error(`${source.label} tidak memiliki kolom: ${missing.join(", ")}.`);
  }
  return { source, buffer, headers, rows: values.slice(1) };
}

function parseCrew(value: unknown, source: typeof sources[number]) {
  const match = /^([ABC])\s+(CP2|PR2)$/i.exec(compact(value));
  if (!match) throw new Error(`${source.label} memiliki format Crew yang tidak dikenali: ${compact(value) || "kosong"}.`);
  const site = match[2].toUpperCase() === "CP2" ? "CPP" : "PORT";
  if (site !== source.site) throw new Error(`${source.label} berisi Crew untuk lokasi ${site}.`);
  return { crew: match[1].toUpperCase(), site };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed." }, 405);

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
  if (callerError || !caller?.is_active) {
    return json({ ok: false, error: "Akun tidak aktif." }, 403);
  }

  try {
    const loaded = await Promise.all(sources.map(readSource));
    const sourceFingerprint = await fingerprint(loaded.map((entry) => entry.buffer));
    const { data: previous } = await admin
      .from("preventive_maintenance_sync_log")
      .select("source_fingerprint")
      .eq("status", "completed")
      .order("completed_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    const now = new Date().toISOString();
    if (previous?.source_fingerprint === sourceFingerprint) {
      await admin.from("preventive_maintenance_sync_log").insert({
        status: "completed",
        snapshot_rows: 0,
        source_fingerprint: sourceFingerprint,
        detail: "Tidak ada perubahan pada CPP PM.xlsx dan PORT PM.xlsx.",
        triggered_by: caller.id,
      });
      return json({ ok: true, changed: false, rows: 0, synced_at: now });
    }

    const rows: Row[] = [];
    for (const loadedSource of loaded) {
      for (const raw of loadedSource.rows) {
        const row = raw as unknown[];
        const workOrder = compact(valueAt(row, loadedSource.headers, "WORK ORDER"));
        if (!workOrder) continue;
        const crew = parseCrew(valueAt(row, loadedSource.headers, "CREW"), loadedSource.source);
        rows.push({
          source_key: `${crew.site}|${workOrder}`,
          work_order: workOrder,
          work_order_description: compact(valueAt(row, loadedSource.headers, "WORK ORDER DESC")),
          equipment_reference: compact(valueAt(row, loadedSource.headers, "EQUIP REF")),
          crew_code: crew.crew,
          site_code: crew.site,
          status_code: compact(valueAt(row, loadedSource.headers, "STATUS")),
          raised_on: dateValue(valueAt(row, loadedSource.headers, "RAISE DTE")),
          planned_start_on: dateValue(valueAt(row, loadedSource.headers, "PLAN START DATE")),
          assigned_to: optional(valueAt(row, loadedSource.headers, "ASSIGN TO")),
          assigned_to_description: optional(valueAt(row, loadedSource.headers, "ASSIGN TO DESCRIPTION")),
          priority: optional(valueAt(row, loadedSource.headers, "ORIGINATOR PRIORITY")),
          priority_description: optional(valueAt(row, loadedSource.headers, "ORIGINATOR PRIORITY DESCRIPTION")),
          source_fingerprint: sourceFingerprint,
          synced_at: now,
        });
      }
    }
    if (rows.length < 20) throw new Error("Jumlah PM yang terbaca terlalu sedikit. Snapshot sebelumnya dipertahankan.");

    const { error: writeError } = await admin
      .from("preventive_maintenance_work_order")
      .upsert(rows, { onConflict: "source_key" });
    if (writeError) throw writeError;
    const { error: deleteError } = await admin
      .from("preventive_maintenance_work_order")
      .delete()
      .in("site_code", ["CPP", "PORT"])
      .neq("source_fingerprint", sourceFingerprint);
    if (deleteError) throw deleteError;
    await admin.from("preventive_maintenance_sync_log").insert({
      status: "completed",
      snapshot_rows: rows.length,
      source_fingerprint: sourceFingerprint,
      detail: "CPP PM.xlsx dan PORT PM.xlsx tervalidasi dan disimpan.",
      triggered_by: caller.id,
    });
    return json({ ok: true, changed: true, rows: rows.length, synced_at: now });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await admin.from("preventive_maintenance_sync_log").insert({
      status: "failed",
      detail: message,
      triggered_by: caller.id,
    });
    return json({ ok: false, error: message }, 500);
  }
});
