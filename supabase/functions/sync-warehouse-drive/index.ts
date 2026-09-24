// Reads the owner's public Drive folder "Gudang" and imports one workbook per
// call: body {"source": "inventory" | "list_order" | "outstanding_po"}.
// The app calls the three sources in parallel, so each stays well inside the
// Edge Function CPU budget. A file whose bytes did not change is only marked
// as checked. Files are picked by name, so re-uploading a new export with a
// different suffix ("Outstanding_Purchase_Order (31).xlsx") still works.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { type Cell, excelSerialToIso, readXlsx, type SheetRows } from "../_shared/lean_xlsx.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const folderId = "1VlT_EfkGY_M1-shqwJndmZ3beO2fAmTg";

type Source = "inventory" | "list_order" | "outstanding_po";

const filePatterns: Record<Source, RegExp> = {
  inventory: /^warehouse[\s_-]*inventory/i,
  list_order: /^list[\s_-]*order/i,
  outstanding_po: /^outstanding[\s_-]*purchase[\s_-]*order/i,
};

const fileLabels: Record<Source, string> = {
  inventory: "Warehouse Inventory",
  list_order: "LIST ORDER",
  outstanding_po: "Outstanding Purchase Order",
};

// Ellipse warehouse IDs grouped by the site names the app filters on.
const warehouseSites: Record<string, string> = {
  AMWH: "Asamasam",
  AFS1: "Asamasam",
  KMWH: "Kintap",
  KMIN: "Kintap",
  KFS1: "Kintap",
  MAIN: "NPLCT",
  CSWH: "NPLCT",
  CMWH: "NPLCT",
  NCH1: "NPLCT",
  NFS1: "NPLCT",
  SNOS: "Senakin",
  SNKN: "Senakin",
  SNFS: "Senakin",
  STOS: "Satui",
  SAWH: "Satui",
  SAFS: "Satui",
  BLWH: "Batulicin",
  BPPN: "Balikpapan",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function text(value: Cell | undefined): string {
  if (value === null || value === undefined) return "";
  return String(value).replace(/\s+/g, " ").trim();
}

function optional(value: Cell | undefined): string | null {
  const result = text(value);
  return result && !/^(null|null - null|-|#n\/a)$/i.test(result) ? result : null;
}

function number(value: Cell | undefined): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  const raw = text(value).replace(/,/g, "");
  if (!raw) return null;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : null;
}

/** "000004675" and "4675" are the same stock code. */
function stockCode(value: Cell | undefined): string | null {
  const raw = text(value).toUpperCase();
  if (!raw || raw === "-") return null;
  return /^\d+$/.test(raw) ? raw.replace(/^0+(?=\d)/, "") : raw;
}

/** Ellipse yyyymmdd; "00000000" means never. */
function compactDate(value: Cell | undefined): string | null {
  const raw = text(value);
  const m = /^(\d{4})(\d{2})(\d{2})$/.exec(raw);
  if (!m || raw === "00000000") return null;
  return `${m[1]}-${m[2]}-${m[3]}`;
}

const months: Record<string, string> = {
  jan: "01", feb: "02", mar: "03", apr: "04", may: "05", jun: "06",
  jul: "07", aug: "08", sep: "09", oct: "10", nov: "11", dec: "12",
};

/** "21 Aug 2026". */
function reportDate(value: Cell | undefined): string | null {
  const m = /^(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})$/.exec(text(value));
  const month = m ? months[m[2].toLowerCase()] : undefined;
  return m && month ? `${m[3]}-${month}-${m[1].padStart(2, "0")}` : null;
}

/** Hand-typed sheet dates: a serial inside a sensible range, else null. */
function sheetDate(value: Cell | undefined, latest: string): string | null {
  if (typeof value !== "number") return null;
  const iso = excelSerialToIso(value);
  return iso && iso >= "2015-01-01" && iso <= latest ? iso : null;
}

/** Excel serial of the report run time, printed in WITA (UTC+8). */
function runTimestamp(value: Cell | undefined): string | null {
  if (typeof value !== "number" || value < 1) return null;
  const utcMs = Date.UTC(1899, 11, 30) + Math.round(value * 86400000) - 8 * 3600000;
  return new Date(utcMs).toISOString();
}

async function fingerprint(bytes: Uint8Array) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function headerIndex(row: Cell[] | undefined): Map<string, number> {
  const result = new Map<string, number>();
  (row ?? []).forEach((value, index) => {
    const key = text(value).toUpperCase();
    if (key && !result.has(key)) result.set(key, index);
  });
  return result;
}

function findHeader(rows: SheetRows, required: string[], limit = 20) {
  for (let i = 0; i < Math.min(rows.length, limit); i++) {
    const header = headerIndex(rows[i]);
    if (required.every((name) => header.has(name))) return { at: i, header };
  }
  return null;
}

async function listFolder(): Promise<{ id: string; name: string }[]> {
  const response = await fetch(`https://drive.google.com/embeddedfolderview?id=${folderId}`, {
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) throw new Error(`Folder Drive Gudang tidak dapat dibaca (HTTP ${response.status}).`);
  const html = await response.text();
  const files: { id: string; name: string }[] = [];
  const re = /href="https:\/\/drive\.google\.com\/file\/d\/([^/"]+)[^"]*"[\s\S]*?class="flip-entry-title">([^<]+)</g;
  for (let m = re.exec(html); m; m = re.exec(html)) {
    files.push({ id: m[1], name: m[2].replace(/&amp;/g, "&").trim() });
  }
  return files;
}

/** The file bytes and its Drive "Date modified" (Last-Modified header). */
async function download(id: string, label: string): Promise<{ bytes: Uint8Array; modifiedAt: string | null }> {
  const response = await fetch(
    `https://drive.usercontent.google.com/download?id=${id}&export=download&confirm=t`,
    { signal: AbortSignal.timeout(60000) },
  );
  if (!response.ok) throw new Error(`${label} tidak dapat diunduh (HTTP ${response.status}).`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  // A PK zip header; Drive answers with an HTML page when a file is private.
  if (bytes[0] !== 0x50 || bytes[1] !== 0x4b) {
    throw new Error(`${label} bukan file .xlsx atau belum dibagikan untuk umum.`);
  }
  const lastModified = response.headers.get("last-modified");
  const time = lastModified ? new Date(lastModified).getTime() : NaN;
  return { bytes, modifiedAt: Number.isFinite(time) ? new Date(time).toISOString() : null };
}

async function insertInBatches(admin: SupabaseClient, table: string, rows: Record<string, unknown>[]) {
  for (let start = 0; start < rows.length; start += 1000) {
    const { error } = await admin.from(table).insert(rows.slice(start, start + 1000));
    if (error) throw error;
  }
}

async function upsertInBatches(admin: SupabaseClient, table: string, rows: Record<string, unknown>[]) {
  for (let start = 0; start < rows.length; start += 1000) {
    const { error } = await admin.from(table).upsert(rows.slice(start, start + 1000), { onConflict: "source_key" });
    if (error) throw error;
  }
}

// Inventory ------------------------------------------------------------------

async function importInventory(admin: SupabaseClient, bytes: Uint8Array, batch: string) {
  const rows = [...readXlsx(bytes, undefined, 24).values()][0] ?? [];
  let reportAt: string | null = null;
  for (const row of rows.slice(0, 12)) {
    const label = text(row?.[1]).toUpperCase();
    if (label.startsWith("RUN DATE")) reportAt = runTimestamp(row[2]);
  }
  const found = findHeader(rows, ["WAREHOUSE ID", "STOCK CODE", "SOH"]);
  if (!found) throw new Error("Kolom Warehouse ID / Stock Code / SOH tidak ditemukan di Warehouse Inventory.");
  const h = found.header;
  const col = (name: string) => h.get(name) ?? -1;
  const lastReceived = [...h.entries()].find(([name]) => name.startsWith("LAST") && name !== "LAST ISSUED")?.[1] ?? -1;
  const { data: sites, error: siteError } = await admin.from("site").select("id,name");
  if (siteError) throw siteError;
  const siteIds = new Map((sites ?? []).map((s) => [String(s.name).toLowerCase(), s.id as string]));
  const reportDay = reportAt ? reportAt.slice(0, 10) : new Date().toISOString().slice(0, 10);
  const now = new Date().toISOString();
  const stock = new Map<string, Record<string, unknown>>();
  for (const row of rows.slice(found.at + 1)) {
    const code = stockCode(row?.[col("STOCK CODE")]);
    const warehouse = text(row?.[col("WAREHOUSE ID")]).toUpperCase();
    const description = text(row?.[col("STOCK CODE DESCRIPTION")]);
    if (!code || !warehouse || warehouse === "TOTAL" || !description) continue;
    const siteLabel = warehouseSites[warehouse] ?? (text(row[col("WAREHOUSE ID DESC")]) || warehouse);
    stock.set(`${code}|${warehouse}`, {
      source_key: `${code}|${warehouse}`,
      item_code: code,
      description,
      warehouse_code: warehouse,
      warehouse_name: optional(row[col("WAREHOUSE ID DESC")]),
      site_label: siteLabel,
      site_id: siteIds.get(siteLabel.toLowerCase()) ?? null,
      uoi: optional(row[col("UOI")]),
      bin_code: optional(row[col("BIN CODE")]),
      unit_price: number(row[col("ITEM PRICE")]),
      stock_on_hand: number(row[col("SOH")]) ?? 0,
      inventory_value: number(row[col("INVENT VALUE")]),
      part_no: optional(row[col("PART NO 1")]),
      part_no_2: optional(row[col("PART NO 2")]),
      stock_class: optional(row[col("STOCK CLASS DESC")]),
      stock_type: optional(row[col("STOCK TYPE DESC")]),
      expense_element: optional(row[col("EXP EL DESCRIPTION")]),
      last_received_on: compactDate(row[lastReceived]),
      last_issued_on: compactDate(row[col("LAST ISSUED")]),
      source_updated_on: reportDay,
      stock_source: "inventory",
      source_batch: batch,
      synced_at: now,
    });
  }
  if (stock.size < 100) throw new Error("Warehouse Inventory berisi terlalu sedikit barang; data lama dipertahankan.");
  await upsertInBatches(admin, "warehouse_stock", [...stock.values()]);
  // Items that left the report disappear, but only for warehouses it covers
  // and only rows an earlier inventory import wrote.
  const warehouses = [...new Set([...stock.values()].map((r) => r.warehouse_code as string))];
  const { error } = await admin
    .from("warehouse_stock")
    .delete()
    .eq("stock_source", "inventory")
    .in("warehouse_code", warehouses)
    .neq("source_batch", batch);
  if (error) throw error;
  return { rows: stock.size, reportAt };
}

// Outstanding purchase orders ---------------------------------------------------

async function importOutstandingPo(admin: SupabaseClient, bytes: Uint8Array, batch: string) {
  const rows = [...readXlsx(bytes, undefined, 16).values()][0] ?? [];
  const found = findHeader(rows, ["PO NO", "DESCRIPTION", "QTY OUTSTANDING"]);
  if (!found) throw new Error("Kolom PO No / Description / Qty Outstanding tidak ditemukan.");
  const h = found.header;
  const col = (name: string) => h.get(name) ?? -1;
  const lines: Record<string, unknown>[] = [];
  for (const row of rows.slice(found.at + 1)) {
    const po = text(row?.[col("PO NO")]).toUpperCase();
    if (!/^[A-Z]?\d+/.test(po)) continue;
    const requestor = optional(row[col("REQUESTOR")]);
    lines.push({
      po_no: po,
      po_item_no: optional(row[col("PO ITEM NO")]),
      supplier_no: optional(row[col("SUPPLIER NO")]),
      supplier_name: optional(row[col("SUPPLIER NAME")]),
      item_code: stockCode(row[col("STOCK CODE")]),
      // "0000003226 - Citra Mulia Setiawan" -> the name.
      requestor: requestor?.replace(/^\S+\s+-\s+/, "") || null,
      warehouse_code: optional(row[col("WAREHOUSE ID")]),
      description: optional(row[col("DESCRIPTION")]),
      part_no: optional(row[col("PART NO")]),
      qty_order: number(row[col("QTY ORDER")]),
      qty_outstanding: number(row[col("QTY OUTSTANDING")]),
      order_date: reportDate(row[col("ORDER DATE")]),
      due_date: reportDate(row[col("DUE DATE")]),
      purchasing_officer: optional(row[col("PURCHASING OFFICER")]),
      source_batch: batch,
    });
  }
  if (lines.length === 0) throw new Error("Outstanding Purchase Order tidak berisi baris PO.");
  await insertInBatches(admin, "warehouse_outstanding_po", lines);
  const { error } = await admin.from("warehouse_outstanding_po").delete().neq("source_batch", batch);
  if (error) throw error;
  return { rows: lines.length, reportAt: null };
}

// LIST ORDER --------------------------------------------------------------------

const loanSheet = "PEMINJAMAN & OUTSTANDING TOOLS";

async function importListOrder(admin: SupabaseClient, bytes: Uint8Array, batch: string) {
  const sheets = readXlsx(bytes, undefined, 12);
  const latest = new Date(Date.now() + 2 * 86400000).toISOString().slice(0, 10);
  const issues: Record<string, unknown>[] = [];
  for (const [name, rows] of sheets) {
    if (name === loanSheet) continue;
    const found = findHeader(rows, ["USER NAME", "SC"], 6);
    if (!found) continue;
    const h = found.header;
    const qty = h.get("QTY") ?? h.get("QYT") ?? -1;
    const note = [...h.entries()].find(([key]) => key.startsWith("KETERANGAN"))?.[1] ?? -1;
    let date: string | null = null;
    rows.slice(found.at + 1).forEach((row, offset) => {
      // A blank date cell means "same day as the row above".
      if (row?.[0] !== null && row?.[0] !== undefined && text(row[0]) !== "") {
        date = sheetDate(row[0], latest);
      }
      const code = stockCode(row?.[h.get("SC") ?? -1]);
      if (!code || !/^\d+$/.test(code)) return;
      const quantity = row[qty];
      issues.push({
        item_code: code,
        issued_on: date,
        user_name: optional(row[h.get("USER NAME") ?? -1]),
        quantity: typeof quantity === "number" ? quantity : number(quantity),
        quantity_text: optional(quantity),
        uoi: optional(row[h.get("UOI") ?? -1]),
        description: optional(row[h.get("DESCRIPTION") ?? -1]),
        ir_no: optional(row[h.get("IR NO") ?? -1]),
        note: optional(row[note]),
        sheet_name: name.trim(),
        row_no: found.at + offset + 2,
        source_batch: batch,
      });
    });
  }
  if (issues.length < 100) throw new Error("LIST ORDER berisi terlalu sedikit pengambilan; data lama dipertahankan.");

  const loans: Record<string, unknown>[] = [];
  let loanDate: string | null = null;
  (sheets.get(loanSheet) ?? []).forEach((row, index) => {
    if (row?.[0] !== null && row?.[0] !== undefined && text(row[0]) !== "") {
      loanDate = sheetDate(row[0], latest);
    }
    const tool = optional(row?.[1]);
    const start = optional(row?.[7]);
    if (!tool || /^(description|remarks)$/i.test(tool) || /^kondisi/i.test(start ?? "")) return;
    const end = optional(row[8]);
    loans.push({
      row_no: index + 1,
      loaned_on: loanDate,
      tool_name: tool,
      quantity: optional(row[2]),
      number_colour: optional(row[3]),
      location: optional(row[4]),
      borrower: optional(row[5]),
      warehouseman: optional(row[6]),
      condition_start: start,
      condition_end: end,
      returned: end !== null,
      source_batch: batch,
    });
  });

  await insertInBatches(admin, "warehouse_issue_history", issues);
  await insertInBatches(admin, "warehouse_list_order_loan", loans);
  for (const table of ["warehouse_issue_history", "warehouse_list_order_loan"]) {
    const { error } = await admin.from(table).delete().neq("source_batch", batch);
    if (error) throw error;
  }
  return { rows: issues.length + loans.length, reportAt: null };
}

// Handler -----------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Metode tidak diizinkan." }, 405);
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

  let source: Source;
  try {
    const body = await req.json() as { source?: string };
    if (!body.source || !(body.source in filePatterns)) throw new Error();
    source = body.source as Source;
  } catch {
    return json({ ok: false, error: "Sumber tidak dikenal." }, 400);
  }
  const label = fileLabels[source];
  const now = new Date().toISOString();

  try {
    const file = (await listFolder()).find((f) => filePatterns[source].test(f.name));
    if (!file) throw new Error(`File ${label} tidak ada di folder Drive Gudang.`);
    const { bytes, modifiedAt } = await download(file.id, label);
    const sourceFingerprint = await fingerprint(bytes);
    const { data: previous, error: previousError } = await admin
      .from("warehouse_drive_source")
      .select("source_fingerprint,row_count,changed_at")
      .eq("source", source)
      .maybeSingle();
    if (previousError) throw previousError;
    if (previous?.source_fingerprint === sourceFingerprint) {
      await admin.from("warehouse_drive_source").update({
        checked_at: now, error: null, error_at: null, file_id: file.id, file_name: file.name,
        ...(modifiedAt ? { modified_at: modifiedAt } : {}),
      }).eq("source", source);
      return json({ ok: true, source, changed: false, rows: previous.row_count, file: file.name });
    }
    const batch = sourceFingerprint.slice(0, 16);
    const result = source === "inventory"
      ? await importInventory(admin, bytes, batch)
      : source === "outstanding_po"
      ? await importOutstandingPo(admin, bytes, batch)
      : await importListOrder(admin, bytes, batch);
    const { error: saveError } = await admin.from("warehouse_drive_source").upsert({
      source,
      file_id: file.id,
      file_name: file.name,
      source_fingerprint: sourceFingerprint,
      report_at: result.reportAt,
      modified_at: modifiedAt,
      row_count: result.rows,
      changed_at: now,
      checked_at: now,
      error: null,
      error_at: null,
    }, { onConflict: "source" });
    if (saveError) throw saveError;
    return json({ ok: true, source, changed: true, rows: result.rows, file: file.name });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : typeof error === "object" && error !== null && "message" in error
      ? String((error as { message: unknown }).message)
      : String(error);
    console.error(`${label} import failed`, message);
    await admin.from("warehouse_drive_source").upsert(
      { source, error: message, error_at: now },
      { onConflict: "source" },
    );
    return json({ ok: false, source, error: message });
  }
});
