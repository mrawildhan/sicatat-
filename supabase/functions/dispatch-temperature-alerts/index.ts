// Emails critical temperatures (>= the critical limit) to the recipients the
// admin lists under Data master -> Penerima peringatan suhu.
//
// Invoked every 5 minutes by Supabase Cron with the same Vault secret as the
// reminder dispatcher; JWT verification is disabled at the gateway for that
// reason. Each critical value gets one temperature_alert row (unique
// source_key), so it is emailed once even though the scan window overlaps.

import { createClient } from "npm:@supabase/supabase-js@2";

import {
  deliverEmail,
  escapeHtml,
  isValidEmail,
} from "../_shared/reminder_email.ts";

type Json = Record<string, unknown>;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const DEFAULT_CRITICAL = 70;
const SCAN_HOURS = 6;

// Mirrors flutter_app/lib/features/daily_checks/daily_check_forms.dart.
const DAILY_FORMS: Record<
  string,
  {
    label: string;
    units: Record<string, string>;
    temperatures: Record<string, string>;
    slots: Record<string, string>;
  }
> = {
  hydraulic_feeder: {
    label: "Daily Check Sheet Hydraulic Feeder",
    units: { f1: "Feeder 1", f2: "Feeder 2" },
    temperatures: {
      ambient: "Ambient temp",
      main_pump: "Main pump",
      hydraulic_motor: "Hydraulic motor",
      flushing_p1: "Flushing valve P1",
      flushing_p2: "Flushing valve P2",
      flushing_t: "Flushing valve T",
      heat_exchanger_a: "Heat exchanger A",
      heat_exchanger_b: "Heat exchanger B",
      heat_exchanger_c: "Heat exchanger C",
    },
    slots: {
      check_1: "Pengecekan I",
      check_2: "Pengecekan II",
      check_3: "Pengecekan III",
    },
  },
  coal_valve: {
    label: "Temperature Coal Valve",
    units: {
      west: "Sisi Barat",
      east: "Sisi Timur",
      north: "Sisi Utara",
      south: "Sisi Selatan",
    },
    temperatures: { rv01: "RV01", rv02: "RV02", rv03: "RV03", rv04: "RV04" },
    slots: {
      reading_1: "Pembacaan 1",
      reading_2: "Pembacaan 2",
      reading_3: "Pembacaan 3",
      reading_4: "Pembacaan 4",
    },
  },
};

function shiftLabel(shift: Json | null | undefined) {
  const code = typeof shift?.code === "string" ? shift.code : "";
  if (code === "PAGI") return "Shift Pagi";
  if (code === "MALAM") return "Shift Malam";
  return typeof shift?.name === "string" ? shift.name : "-";
}

function witaTime(value: string) {
  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Makassar",
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));
}

type AlertRow = {
  source: "daily_check" | "sheet";
  source_key: string;
  site_id: string | null;
  team_id: string | null;
  form_label: string;
  point_label: string;
  value: number;
  limit_value: number;
  sheet_date: string | null;
  shift_label: string | null;
  occurred_at: string;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ ok: false, error: "Method not allowed." }, 405);
  }
  const expectedSecret = Deno.env.get("REMINDER_CRON_SECRET");
  if (
    !expectedSecret ||
    req.headers.get("x-reminder-cron-secret") !== expectedSecret
  ) {
    return json({ ok: false, error: "Unauthorized scheduler request." }, 401);
  }
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const since = new Date(Date.now() - SCAN_HOURS * 3600_000).toISOString();

  try {
    // Per-point limits for the daily check sheets.
    const { data: thresholds, error: thresholdError } = await admin
      .from("daily_check_threshold")
      .select("form_type,field_key,critical_from");
    if (thresholdError) throw thresholdError;
    const critical = new Map<string, number>();
    for (const row of thresholds ?? []) {
      critical.set(row.form_type + ":" + row.field_key, Number(row.critical_from));
    }

    const found: AlertRow[] = [];

    // 1. Daily check sheets changed recently.
    const { data: sheets, error: sheetError } = await admin
      .from("daily_check_sheet")
      .select(
        "id,form_type,tanggal,site_id,team_id,readings,updated_at,shift:shift_id(name,code),team:team_id(name)",
      )
      .gte("updated_at", since)
      .limit(500);
    if (sheetError) throw sheetError;
    for (const sheet of sheets ?? []) {
      const form = DAILY_FORMS[sheet.form_type as string];
      if (!form) continue;
      const readings = (sheet.readings ?? {}) as Record<string, Json>;
      for (const [slotKey, values] of Object.entries(readings)) {
        for (const [unitKey, unitLabel] of Object.entries(form.units)) {
          for (const [fieldKey, fieldLabel] of Object.entries(form.temperatures)) {
            const value = values?.[unitKey + "." + fieldKey];
            if (typeof value !== "number") continue;
            const limit =
              critical.get(sheet.form_type + ":" + fieldKey) ?? DEFAULT_CRITICAL;
            if (value < limit) continue;
            const recorded =
              typeof values.recorded_at === "string"
                ? values.recorded_at
                : (sheet.updated_at as string);
            found.push({
              source: "daily_check",
              source_key: [sheet.id, slotKey, unitKey, fieldKey].join(":"),
              site_id: sheet.site_id as string,
              team_id: sheet.team_id as string,
              form_label: form.label,
              point_label:
                (form.slots[slotKey] ?? slotKey) + " - " + unitLabel + " - " + fieldLabel,
              value,
              limit_value: limit,
              sheet_date: sheet.tanggal as string,
              shift_label: shiftLabel(sheet.shift as Json),
              occurred_at: recorded,
            });
          }
        }
      }
    }

    // 2. Feeder/Sizer temperature readings saved recently.
    const { data: readings, error: readingError } = await admin
      .from("reading")
      .select(
        "id,value_numeric,measured_at,measurement_point:measurement_point_id(label,unit,data_type),round:round_id(section,round_number,sheet:sheet_id(tanggal,site_id,team_id,shift:shift_id(name,code)))",
      )
      .gte("created_at", since)
      .gte("value_numeric", DEFAULT_CRITICAL)
      .limit(500);
    if (readingError) throw readingError;
    for (const reading of readings ?? []) {
      const point = reading.measurement_point as Json | null;
      if (point?.data_type !== "numeric") continue;
      const round = reading.round as Json | null;
      const sheet = round?.sheet as Json | null;
      const section = round?.section === "gearbox_sizer" ? "Gearbox Sizer" : "Gearbox Breaker";
      found.push({
        source: "sheet",
        source_key: "reading:" + reading.id,
        site_id: (sheet?.site_id as string) ?? null,
        team_id: (sheet?.team_id as string) ?? null,
        form_label: "Daily Temperature Feeder Sizer",
        point_label:
          section + " Ronde " + String(round?.round_number ?? "") + " - " + String(point?.label ?? ""),
        value: Number(reading.value_numeric),
        limit_value: DEFAULT_CRITICAL,
        sheet_date: (sheet?.tanggal as string) ?? null,
        shift_label: shiftLabel(sheet?.shift as Json),
        occurred_at: reading.measured_at as string,
      });
    }

    if (found.length > 0) {
      const { error } = await admin
        .from("temperature_alert")
        .upsert(found, { onConflict: "source_key", ignoreDuplicates: true });
      if (error) throw error;
    }

    // 3. Email everything still pending, one message per site.
    const { data: pending, error: pendingError } = await admin
      .from("temperature_alert")
      .select("*,site:site_id(name),team:team_id(name)")
      .eq("status", "pending")
      .order("occurred_at", { ascending: true })
      .limit(200);
    if (pendingError) throw pendingError;
    const { data: recipients, error: recipientError } = await admin
      .from("temperature_alert_recipient")
      .select("email,site_id")
      .eq("is_active", true);
    if (recipientError) throw recipientError;

    const bySite = new Map<string, Json[]>();
    for (const alert of pending ?? []) {
      const key = (alert.site_id as string) ?? "";
      bySite.set(key, [...(bySite.get(key) ?? []), alert]);
    }

    let sent = 0;
    let failed = 0;
    let noRecipient = 0;
    for (const [siteId, alerts] of bySite) {
      const to = [
        ...new Set(
          (recipients ?? [])
            .filter((r) => !r.site_id || r.site_id === siteId)
            .map((r) => String(r.email).trim().toLowerCase())
            .filter(isValidEmail),
        ),
      ];
      const ids = alerts.map((a) => a.id as string);
      if (to.length === 0) {
        await admin.from("temperature_alert").update({ status: "no_recipient" }).in("id", ids);
        noRecipient += ids.length;
        continue;
      }
      const siteName = ((alerts[0].site as Json | null)?.name as string) ?? "-";
      const rows = alerts
        .map((a) => {
          const team = ((a.team as Json | null)?.name as string) ?? "-";
          return `<tr>
            <td style="padding:8px;border:1px solid #f1c3bf">${escapeHtml(witaTime(a.occurred_at as string))}</td>
            <td style="padding:8px;border:1px solid #f1c3bf">${escapeHtml(a.form_label as string)}<br><small>${escapeHtml(team)} - ${escapeHtml((a.shift_label as string) ?? "-")}</small></td>
            <td style="padding:8px;border:1px solid #f1c3bf">${escapeHtml(a.point_label as string)}</td>
            <td style="padding:8px;border:1px solid #f1c3bf;color:#b91c1c;font-weight:700;text-align:center">${escapeHtml(String(a.value))} &deg;C</td>
          </tr>`;
        })
        .join("");
      const html = `
        <div style="padding:20px 12px;background:#f4f7f5;font-family:Arial,Helvetica,sans-serif;color:#17221d">
          <div style="max-width:680px;margin:0 auto;background:#fff;border:1px solid #dce7e0;border-radius:16px;overflow:hidden">
            <div style="padding:20px 24px;background:#b91c1c;color:#fff">
              <div style="font-size:11px;letter-spacing:.12em;font-weight:700;opacity:.85">SICATAT - PERINGATAN SUHU KRITIS</div>
              <h1 style="margin:8px 0 0;font-size:22px">${alerts.length} pembacaan kritis di ${escapeHtml(siteName)}</h1>
            </div>
            <div style="padding:20px 24px">
              <p style="margin:0 0 14px;font-size:14px;line-height:1.5">Nilai berikut mencapai batas kritis. Periksa unit di lapangan dan tindak lanjuti sesuai prosedur.</p>
              <table style="width:100%;border-collapse:collapse;font-size:13px">
                <tr style="background:#fdecea"><th style="padding:8px;border:1px solid #f1c3bf;text-align:left">Waktu (WITA)</th><th style="padding:8px;border:1px solid #f1c3bf;text-align:left">Lembar</th><th style="padding:8px;border:1px solid #f1c3bf;text-align:left">Titik ukur</th><th style="padding:8px;border:1px solid #f1c3bf">Suhu</th></tr>
                ${rows}
              </table>
              <p style="margin:16px 0 0;font-size:12px;color:#6d7a73">Email otomatis SICATAT. Penerima diatur admin di Data master &rarr; Penerima peringatan suhu.</p>
            </div>
          </div>
        </div>`;
      const text = [
        "SICATAT - PERINGATAN SUHU KRITIS",
        alerts.length + " pembacaan kritis di " + siteName,
        "",
        ...alerts.map(
          (a) =>
            witaTime(a.occurred_at as string) + " | " + a.form_label + " | " +
            (((a.team as Json | null)?.name as string) ?? "-") + " | " + a.point_label +
            " | " + a.value + " C",
        ),
      ].join("\n");
      try {
        await deliverEmail({
          recipients: to,
          subject: "[KRITIS] Suhu " + siteName + " - " + alerts.length + " pembacaan >= batas",
          html,
          text,
        });
        await admin
          .from("temperature_alert")
          .update({ status: "sent", sent_at: new Date().toISOString(), error: null })
          .in("id", ids);
        sent += ids.length;
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        await admin
          .from("temperature_alert")
          .update({ status: "failed", error: message.slice(0, 500) })
          .in("id", ids);
        failed += ids.length;
      }
    }

    return json({ ok: true, found: found.length, sent, failed, noRecipient });
  } catch (error) {
    console.error(error);
    return json(
      { ok: false, error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
