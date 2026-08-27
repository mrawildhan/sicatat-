// Invoked once a day by Supabase Cron. This function deliberately disables JWT
// verification at the gateway, then verifies an unguessable server-side header
// sourced from Supabase Vault before sending anything.

import { createClient } from "npm:@supabase/supabase-js@2";

import {
  sendReminderEmail,
  type ReminderEmailRecord,
} from "../_shared/reminder_email.ts";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function dateInWita() {
  const pieces = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Makassar",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const value = (type: string) =>
    pieces.find((part) => part.type === type)?.value ?? "";
  return value("year") + "-" + value("month") + "-" + value("day");
}

function daysBetween(startDate: string, endDate: string) {
  const start = Date.parse(startDate + "T00:00:00Z");
  const end = Date.parse(endDate + "T00:00:00Z");
  return Math.round((end - start) / 86400000);
}

function subtractDays(date: string, days: number) {
  const value = new Date(date + "T00:00:00Z");
  value.setUTCDate(value.getUTCDate() - days);
  return value.toISOString().slice(0, 10);
}

function subtractOneCalendarMonth(date: string) {
  const [year, month, day] = date.split("-").map(Number);
  const targetMonth = month === 1 ? 12 : month - 1;
  const targetYear = month === 1 ? year - 1 : year;
  const lastDay = new Date(Date.UTC(targetYear, targetMonth, 0)).getUTCDate();
  return [
    String(targetYear).padStart(4, "0"),
    String(targetMonth).padStart(2, "0"),
    String(Math.min(day, lastDay)).padStart(2, "0"),
  ].join("-");
}

type ScheduledReminder = {
  reminder: ReminderEmailRecord & {
    reminder_schedule?: unknown;
    custom_reminder_days?: unknown;
    reminder_offsets_days?: unknown;
  };
  offsetDays: number;
  scheduleType: "weekly" | "monthly" | "custom" | "legacy";
};

function scheduledToday(
  reminder: ScheduledReminder["reminder"],
  today: string,
): ScheduledReminder[] {
  const dueDate =
    typeof reminder.due_date === "string" ? reminder.due_date : "";
  if (!dueDate) return [];
  const schedule = reminder.reminder_schedule;
  if (schedule === "weekly") {
    return subtractDays(dueDate, 7) === today
      ? [{ reminder, offsetDays: 7, scheduleType: "weekly" }]
      : [];
  }
  if (schedule === "monthly") {
    return subtractOneCalendarMonth(dueDate) === today
      ? [
          {
            reminder,
            offsetDays: daysBetween(today, dueDate),
            scheduleType: "monthly",
          },
        ]
      : [];
  }
  if (schedule === "custom") {
    const customDays =
      typeof reminder.custom_reminder_days === "number"
        ? reminder.custom_reminder_days
        : null;
    return customDays !== null && subtractDays(dueDate, customDays) === today
      ? [{ reminder, offsetDays: customDays, scheduleType: "custom" }]
      : [];
  }

  // Legacy rows from before the schedule migration retain their saved offsets.
  const offsets = Array.isArray(reminder.reminder_offsets_days)
    ? reminder.reminder_offsets_days.filter(
        (value): value is number => typeof value === "number",
      )
    : [];
  const offset = daysBetween(today, dueDate);
  return offsets.includes(offset)
    ? [{ reminder, offsetDays: offset, scheduleType: "legacy" }]
    : [];
}

Deno.serve(async (req) => {
  if (req.method !== "POST")
    return json({ ok: false, error: "Method not allowed." }, 405);
  const expectedSecret = Deno.env.get("REMINDER_CRON_SECRET");
  if (
    !expectedSecret ||
    req.headers.get("x-reminder-cron-secret") !== expectedSecret
  ) {
    return json({ ok: false, error: "Unauthorized scheduler request." }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceRoleKey);
  const today = dateInWita();

  try {
    const { data: reminders, error } = await admin
      .from("operational_reminder")
      .select(
        "id,title,due_date,recipient_emails,category,asset_code,description,priority,assigned_to,location,reminder_schedule,custom_reminder_days,reminder_offsets_days,site:site_id(name,code)",
      )
      .eq("status", "open")
      .gte("due_date", today)
      .limit(100);
    if (error) throw error;

    const dueToday = (reminders ?? []).flatMap((reminder) =>
      scheduledToday(reminder as ScheduledReminder["reminder"], today),
    );
    let sent = 0;
    let skipped = 0;
    let failed = 0;

    for (const scheduled of dueToday) {
      const reminder = scheduled.reminder;
      const reminderId = String(reminder.id);
      const dueDate = String(reminder.due_date);
      const { data: delivery, error: claimError } = await admin
        .from("operational_reminder_delivery")
        .insert({
          reminder_id: reminderId,
          delivery_type: "scheduled",
          scheduled_offset_days: scheduled.offsetDays,
          scheduled_schedule_type: scheduled.scheduleType,
          due_date_snapshot: dueDate,
          recipients: reminder.recipient_emails,
          status: "sending",
        })
        .select("id")
        .single();
      if (claimError || !delivery) {
        if (claimError?.code === "23505") {
          skipped += 1;
          continue;
        }
        console.error(
          "Unable to claim scheduled reminder",
          reminderId,
          claimError,
        );
        failed += 1;
        continue;
      }

      try {
        const result = await sendReminderEmail(reminder);
        await admin
          .from("operational_reminder_delivery")
          .update({
            status: "sent",
            provider_id: result.providerId,
            recipients: result.recipients,
            sent_at: new Date().toISOString(),
          })
          .eq("id", delivery.id);
        await admin
          .from("operational_reminder")
          .update({ last_sent_at: new Date().toISOString() })
          .eq("id", reminderId);
        await admin.from("operational_reminder_activity").insert({
          reminder_id: reminderId,
          action: "email_sent",
          note:
            "Automatic " +
            scheduled.scheduleType +
            " email sent to " +
            result.recipients.length +
            " recipient(s).",
          details: {
            delivery_id: delivery.id,
            delivery_type: "scheduled",
            offset_days: scheduled.offsetDays,
            schedule_type: scheduled.scheduleType,
          },
        });
        sent += 1;
      } catch (sendError) {
        const message =
          sendError instanceof Error
            ? sendError.message
            : "Unable to send reminder email.";
        await admin
          .from("operational_reminder_delivery")
          .update({ status: "failed", error_message: message })
          .eq("id", delivery.id);
        console.error("Scheduled reminder failed", reminderId, message);
        failed += 1;
      }
    }
    return json({
      ok: true,
      date: today,
      considered: dueToday.length,
      sent,
      skipped,
      failed,
    });
  } catch (error) {
    console.error(error);
    return json(
      {
        ok: false,
        error:
          error instanceof Error
            ? error.message
            : "Unable to dispatch reminders.",
      },
      500,
    );
  }
});
