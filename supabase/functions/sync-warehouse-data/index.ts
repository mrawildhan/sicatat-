// Synchronises the approved public Google Sheets into a Supabase search
// snapshot. The mobile app never reads Google Sheets directly.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const source = {
  itemMaster:
    "https://docs.google.com/spreadsheets/d/1XJbrZd7SnP2WAWA8W8bZ8hIdxe3IRuKHqf0QTCQtMDc/gviz/tq?tqx=out:csv&gid=1873303921",
  allSiteStock:
    "https://docs.google.com/spreadsheets/d/1VL4peqRwRUBDvokuSY-ucoP96mr-3ISRkrEc9tH8w-M/gviz/tq?tqx=out:csv&gid=0",
  receipts:
    "https://docs.google.com/spreadsheets/d/1i__II9Uraw-67xXdiSB8iVz5wirryvpKUiyu2A38qIQ/gviz/tq?tqx=out:csv&gid=0",
  kintapInventory:
    "https://docs.google.com/spreadsheets/d/1_SbyAVTrDoPCqJHOwfiya-TffiU7CIFgiUgqwXJxfYk/gviz/tq?tqx=out:csv&gid=0",
  toolRegister:
    "https://docs.google.com/spreadsheets/d/1nzKdmxZFdq47ukSONUjHGo8JGHBSZRFidDlzorVjk-8/gviz/tq?tqx=out:csv&gid=0",
};

const siteLabels: Record<string, string> = {
  AMWH: "Asamasam",
  KMWH: "Kintap",
  MAIN: "Main warehouse",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function parseCsv(value: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;
  for (let index = 0; index < value.length; index += 1) {
    const character = value[index];
    if (character === '"') {
      if (quoted && value[index + 1] === '"') {
        cell += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === "," && !quoted) {
      row.push(cell.trim());
      cell = "";
    } else if ((character === "\n" || character === "\r") && !quoted) {
      if (character === "\r" && value[index + 1] === "\n") index += 1;
      row.push(cell.trim());
      if (row.some((entry) => entry.length > 0)) rows.push(row);
      row = [];
      cell = "";
    } else {
      cell += character;
    }
  }
  row.push(cell.trim());
  if (row.some((entry) => entry.length > 0)) rows.push(row);
  return rows;
}

function headerIndex(header: string[]) {
  const result = new Map<string, number>();
  header.forEach((name, index) => result.set(name.trim().toUpperCase(), index));
  return result;
}

function valueAt(row: string[], headers: Map<string, number>, name: string) {
  return row[headers.get(name) ?? -1]?.trim() ?? "";
}

function numberValue(value: string) {
  const compact = value.replace(/\s/g, "");
  if (!compact) return null;
  const normalised = compact.includes(",")
    ? compact.replace(/\./g, "").replace(",", ".")
    : compact;
  const parsed = Number(normalised);
  return Number.isFinite(parsed) ? parsed : null;
}

function dateValue(value: string) {
  const compact = value.trim();
  if (/^\d{8}$/.test(compact)) {
    return `${compact.slice(0, 4)}-${compact.slice(4, 6)}-${compact.slice(6, 8)}`;
  }
  const match = /^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/.exec(compact);
  if (!match) return null;
  const year = match[3].length === 2 ? 2000 + Number(match[3]) : Number(match[3]);
  return [year, Number(match[2]), Number(match[1])]
    .map((part, index) => String(part).padStart(index === 0 ? 4 : 2, "0"))
    .join("-");
}

type SheetRows = { headers: Map<string, number>; rows: string[][] };

async function fetchRows(url: string, label: string, minimumRows: number): Promise<SheetRows> {
  const response = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (!response.ok) throw new Error(`${label} could not be read (HTTP ${response.status}).`);
  const rows = parseCsv(await response.text());
  if (rows.length - 1 < minimumRows) {
    throw new Error(`${label} has too few data rows. The previous Warehouse snapshot was kept.`);
  }
  return { headers: headerIndex(rows[0]), rows: rows.slice(1) };
}

function requireColumns(sheet: SheetRows, label: string, names: string[]) {
  const missing = names.filter((name) => !sheet.headers.has(name));
  if (missing.length > 0) {
    throw new Error(`${label} is missing required column(s): ${missing.join(", ")}. The previous Warehouse snapshot was kept.`);
  }
}

function lastLogDate(note: string) {
  const dates = [...note.matchAll(/Log Update\s*\((\d{4}-\d{2}-\d{2})\)/gi)]
    .map((match) => match[1])
    .sort();
  return dates.length > 0 ? dates[dates.length - 1] : null;
}

function chunks<T>(items: T[], size = 500) {
  const result: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    result.push(items.slice(index, index + size));
  }
  return result;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ ok: false, error: "No login session." }, 401);

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await callerClient.auth.getUser();
  if (authError || !user?.email) return json({ ok: false, error: "Invalid session." }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const nik = user.email.replace("@sicatat.local", "");
  const { data: caller, error: callerError } = await admin
    .from("app_user")
    .select("id,role,is_active")
    .eq("nik", nik)
    .single();
  if (
    callerError || !caller || !caller.is_active ||
    !["admin", "supervisor_smg", "warehouseman"].includes(caller.role)
  ) {
    return json({ ok: false, error: "Your role is not allowed to synchronise Warehouse data." }, 403);
  }

  const { data: log, error: logError } = await admin
    .from("warehouse_sync_log")
    .insert({ status: "running", triggered_by: caller.id })
    .select("id")
    .single();
  if (logError || !log) return json({ ok: false, error: "Unable to start the Warehouse sync." }, 500);

  try {
    // Read and validate every source before writing anything. A partially edited
    // Sheet therefore fails safely and leaves the last good mobile snapshot intact.
    const [master, stock, receipts, kintapInventory, toolRegister, sitesResponse] = await Promise.all([
      fetchRows(source.itemMaster, "SCMASTER", 5),
      fetchRows(source.allSiteStock, "SCALLSITE", 100),
      fetchRows(source.receipts, "PENERIMAAN", 20),
      fetchRows(source.kintapInventory, "DST Kintap inventory", 20),
      fetchRows(source.toolRegister, "PEMINJAMAMAN tool register", 10),
      admin.from("site").select("id,name").eq("is_active", true),
    ]);
    if (sitesResponse.error) throw sitesResponse.error;
    requireColumns(master, "SCMASTER", ["SC ITEM", "UOI", "BIN CODE"]);
    requireColumns(stock, "SCALLSITE", ["SC", "DESC", "SITE", "HARGA", "SOH", "TANGGAL UPDATE"]);
    requireColumns(receipts, "PENERIMAAN", ["TANGGAL", "NO PO", "DESKRIPSI PR"]);
    requireColumns(kintapInventory, "DST Kintap inventory", [
      "WAREHOUSE ID", "STOCK CODE", "STOCK CODE DESCRIPTION", "BIN CODE", "UOI", "SOH", "ITEM PRICE",
    ]);
    const siteIdByName = new Map(
      (sitesResponse.data ?? []).map((site) => [site.name.toLowerCase(), site.id]),
    );
    const masterByItem = new Map<string, { uoi: string | null; bin: string | null }>();
    for (const row of master.rows) {
      const itemCode = valueAt(row, master.headers, "SC ITEM");
      if (itemCode) {
        masterByItem.set(itemCode, {
          uoi: valueAt(row, master.headers, "UOI") || null,
          bin: valueAt(row, master.headers, "BIN CODE") || null,
        });
      }
    }

    const aggregated = new Map<string, Record<string, unknown>>();
    for (const row of stock.rows) {
      const itemCode = valueAt(row, stock.headers, "SC");
      const warehouseCode = valueAt(row, stock.headers, "SITE").toUpperCase();
      const description = valueAt(row, stock.headers, "DESC");
      if (!itemCode || !warehouseCode || !description) continue;
      const sourceKey = itemCode + "|" + warehouseCode;
      const existing = aggregated.get(sourceKey);
      const masterItem = masterByItem.get(itemCode);
      const stockOnHand = numberValue(valueAt(row, stock.headers, "SOH")) ?? 0;
      const unitPrice = numberValue(valueAt(row, stock.headers, "HARGA"));
      const siteLabel = siteLabels[warehouseCode] ?? warehouseCode;
      aggregated.set(sourceKey, {
        source_key: sourceKey,
        item_code: itemCode,
        description,
        warehouse_code: warehouseCode,
        site_label: siteLabel,
        site_id: siteIdByName.get(siteLabel.toLowerCase()) ?? null,
        uoi: masterItem?.uoi ?? null,
        bin_code: masterItem?.bin ?? null,
        unit_price: unitPrice ?? existing?.unit_price ?? null,
        stock_on_hand: stockOnHand + Number(existing?.stock_on_hand ?? 0),
        source_updated_on: dateValue(valueAt(row, stock.headers, "TANGGAL UPDATE")),
        synced_at: new Date().toISOString(),
      });
    }
    // DST is a more detailed Kintap source. It enriches matching SCALLSITE rows
    // (price, UOI and bin) and adds any Kintap item not yet listed there.
    for (const row of kintapInventory.rows) {
      const itemCode = valueAt(row, kintapInventory.headers, "STOCK CODE");
      const warehouseCode = valueAt(row, kintapInventory.headers, "WAREHOUSE ID").toUpperCase();
      const description = valueAt(row, kintapInventory.headers, "STOCK CODE DESCRIPTION");
      if (!itemCode || !warehouseCode || !description) continue;
      const sourceKey = itemCode + "|" + warehouseCode;
      const existing = aggregated.get(sourceKey);
      const siteLabel = siteLabels[warehouseCode] ?? "Kintap";
      const detailedStock = numberValue(valueAt(row, kintapInventory.headers, "SOH"));
      aggregated.set(sourceKey, {
        source_key: sourceKey,
        item_code: itemCode,
        description,
        warehouse_code: warehouseCode,
        site_label: siteLabel,
        site_id: siteIdByName.get(siteLabel.toLowerCase()) ?? null,
        uoi: valueAt(row, kintapInventory.headers, "UOI") || existing?.uoi || null,
        bin_code: valueAt(row, kintapInventory.headers, "BIN CODE") || existing?.bin_code || null,
        unit_price: numberValue(valueAt(row, kintapInventory.headers, "ITEM PRICE")) ?? existing?.unit_price ?? null,
        stock_on_hand: detailedStock ?? Number(existing?.stock_on_hand ?? 0),
        // SCALLSITE's TANGGAL UPDATE is the snapshot date. DST's LAST is a
        // record-level history date, so it is only used when no SCALLSITE row
        // exists and never makes a current sheet look older than it is.
        source_updated_on: existing?.source_updated_on ?? dateValue(valueAt(row, kintapInventory.headers, "LAST")) ?? null,
        synced_at: new Date().toISOString(),
      });
    }
    const stockRows = [...aggregated.values()];
    for (const batch of chunks(stockRows)) {
      const { error } = await admin.from("warehouse_stock").upsert(batch, { onConflict: "source_key" });
      if (error) throw error;
    }

    const receiptRows = receipts.rows
      .map((row, index) => ({
        source_key: "po-pr|" + [
          valueAt(row, receipts.headers, "TANGGAL"),
          valueAt(row, receipts.headers, "NO PO"),
          valueAt(row, receipts.headers, "NO ITEM"),
          valueAt(row, receipts.headers, "STOCKODE"),
          valueAt(row, receipts.headers, "DESKRIPSI PR"),
          index,
        ].join("|"),
        received_on: dateValue(valueAt(row, receipts.headers, "TANGGAL")),
        po_number: valueAt(row, receipts.headers, "NO PO") || null,
        item_code: valueAt(row, receipts.headers, "NO ITEM") || null,
        stock_code: valueAt(row, receipts.headers, "STOCKODE") || null,
        description: valueAt(row, receipts.headers, "DESKRIPSI PR") || null,
        quantity: numberValue(valueAt(row, receipts.headers, "QTY")),
        uoi: valueAt(row, receipts.headers, "UOI") || null,
        delivery_note: valueAt(row, receipts.headers, "NO DO") || null,
        supplier: valueAt(row, receipts.headers, "SUPPLYER") || valueAt(row, receipts.headers, "SUPLYER") || null,
        requested_by: valueAt(row, receipts.headers, "USER") || null,
        synced_at: new Date().toISOString(),
      }))
      .filter((row) => row.po_number || row.description);
    for (const batch of chunks(receiptRows)) {
      const { error } = await admin.from("warehouse_receipt").upsert(batch, { onConflict: "source_key" });
      if (error) throw error;
    }

    // The PEMINJAMAMAN sheet has six fixed columns but its first row is a
    // descriptive sample, not a normal header. Keep parsing position-based so
    // operators can update rows without changing the app contract.
    const parsedTools = toolRegister.rows
      .filter((row) => row[0] && !row[0].toUpperCase().startsWith("KODE REGISTRASI"))
      .map((row) => ({
        source_key: "kintap-tool|" + row[0],
        registration_code: row[0],
        tool_name: row[1] || "Unnamed tool",
        mnemonic: row[2] || null,
        serial_number: row[3] || null,
        tool_status: row[4] || null,
        note: row[5] || null,
        last_log_on: lastLogDate(row[5] || ""),
        site_label: "Kintap",
        site_id: siteIdByName.get("kintap") ?? null,
        synced_at: new Date().toISOString(),
      }))
      .filter((row) => row.registration_code && row.tool_name);
    // A registration code can appear more than once in the operator's log.
    // Keep the record with the latest dated activity so a batch upsert is unique.
    const toolsByKey = new Map<string, typeof parsedTools[number]>();
    for (const tool of parsedTools) {
      const current = toolsByKey.get(tool.source_key);
      if (!current || (tool.last_log_on ?? "") >= (current.last_log_on ?? "")) {
        toolsByKey.set(tool.source_key, tool);
      }
    }
    const tools = [...toolsByKey.values()];
    if (tools.length < 10) {
      throw new Error("PEMINJAMAMAN tool register has too few usable records. The previous Warehouse snapshot was kept.");
    }
    for (const batch of chunks(tools)) {
      const { error } = await admin.from("warehouse_tool").upsert(batch, { onConflict: "source_key" });
      if (error) throw error;
    }

    await admin.from("warehouse_sync_log").update({
      status: "completed",
      stock_rows: stockRows.length,
      item_master_rows: masterByItem.size,
      tool_rows: tools.length,
      source_summary: {
        scallsite_rows: stock.rows.length,
        scmaster_rows: masterByItem.size,
        penerimaan_rows: receiptRows.length,
        dst_kintap_rows: kintapInventory.rows.length,
        tool_register_rows: tools.length,
      },
      detail: "Validated and read SCALLSITE, SCMASTER, PENERIMAAN, DST Kintap inventory, and PEMINJAMAMAN tool register.",
      completed_at: new Date().toISOString(),
    }).eq("id", log.id);
    return json({ ok: true, stock_rows: stockRows.length, receipt_rows: receiptRows.length, tool_rows: tools.length });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : typeof error === "string"
      ? error
      : JSON.stringify(error) || "Warehouse synchronisation failed.";
    console.error("Warehouse synchronisation failed:", error);
    await admin.from("warehouse_sync_log").update({
      status: "failed",
      detail: message,
      completed_at: new Date().toISOString(),
    }).eq("id", log.id);
    return json({ ok: false, error: message }, 500);
  }
});
