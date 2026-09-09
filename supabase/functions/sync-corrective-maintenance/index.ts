import { createClient } from "npm:@supabase/supabase-js@2";
import * as XLSX from "npm:xlsx@0.18.5";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const sourceUrl = "https://drive.google.com/uc?export=download&id=1MXeJk9xIGKNEhxGhpFS-cWl9L03fMwwy";

const compact = (value: unknown) => String(value ?? "").trim();
const optional = (value: unknown) => compact(value) || null;
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

function dateValue(value: unknown) {
  const raw = compact(value);
  if (!raw) return null;
  const iso = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(raw);
  if (iso) return `${iso[1]}-${iso[2].padStart(2, "0")}-${iso[3].padStart(2, "0")}`;
  const dmy = /^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$/.exec(raw);
  if (!dmy) return null;
  const year = dmy[3].length === 2 ? 2000 + Number(dmy[3]) : Number(dmy[3]);
  return `${year.toString().padStart(4, "0")}-${dmy[2].padStart(2, "0")}-${dmy[1].padStart(2, "0")}`;
}

function headerIndex(header: unknown[]) {
  const result = new Map<string, number>();
  header.forEach((value, index) => result.set(compact(value).toUpperCase(), index));
  return result;
}

async function fingerprint(buffer: ArrayBuffer) {
  const digest = await crypto.subtle.digest("SHA-256", buffer);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed." }, 405);
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ ok: false, error: "Sesi login diperlukan." }, 401);
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const callerClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: { user } } = await callerClient.auth.getUser();
  if (!user?.email) return json({ ok: false, error: "Sesi login tidak valid." }, 401);
  const admin = createClient(supabaseUrl, serviceRoleKey);
  const nik = user.email.replace("@sicatat.local", "");
  const { data: caller } = await admin.from("app_user").select("id,is_active").eq("nik", nik).maybeSingle();
  if (!caller?.is_active) return json({ ok: false, error: "Akun tidak aktif." }, 403);

  try {
    const response = await fetch(sourceUrl, { signal: AbortSignal.timeout(20000) });
    if (!response.ok) throw new Error(`CM terbaru.xlsx tidak dapat dibaca (HTTP ${response.status}).`);
    const buffer = await response.arrayBuffer();
    const sourceFingerprint = await fingerprint(buffer);
    const workbook = XLSX.read(buffer, { type: "array", cellDates: false });
    const now = new Date().toISOString();
    const rows: Record<string, unknown>[] = [];
    for (const [sheetName, site] of [["CPP", "CPP"], ["Port", "PORT"]] as const) {
      const sheet = workbook.Sheets[sheetName];
      if (!sheet) throw new Error(`Sheet ${sheetName} tidak ditemukan.`);
      const values = XLSX.utils.sheet_to_json<unknown[]>(sheet, { header: 1, defval: "", raw: false });
      const headers = headerIndex(values[1] ?? []);
      for (const raw of values.slice(2)) {
        const row = raw as unknown[];
        const workOrder = compact(row[headers.get("WORK ORDER") ?? -1]);
        if (!workOrder) continue;
        rows.push({
          source_key: `${site}|${workOrder}`,
          work_order: workOrder,
          work_order_description: compact(row[headers.get("WORK ORDER DESC") ?? -1]),
          equipment_reference: compact(row[headers.get("EQUIP REF") ?? -1]),
          site_code: site,
          priority: optional(row[headers.get("PRIORITY") ?? -1]),
          raised_on: dateValue(row[headers.get("RAISE DTE") ?? -1]),
          latest_progress: optional(row[6]),
          source_fingerprint: sourceFingerprint,
          synced_at: now,
        });
      }
    }
    if (rows.length < 2) throw new Error("Jumlah CM yang terbaca terlalu sedikit.");
    const { error: writeError } = await admin.from("corrective_maintenance_work_order").upsert(rows, { onConflict: "source_key" });
    if (writeError) throw writeError;
    const { error: deleteError } = await admin.from("corrective_maintenance_work_order").delete().neq("source_fingerprint", sourceFingerprint);
    if (deleteError) throw deleteError;
    return json({ ok: true, changed: true, rows: rows.length, synced_at: now });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return json({ ok: false, error: message }, 500);
  }
});
