// Manual reminder delivery is available to admin, Supervisor SMG, and Foreman
// LV. Foreman LV is intentionally global for reminders only. Mail credentials remain in Edge Function secrets;
// Flutter only supplies a reminder ID.

import { createClient } from "npm:@supabase/supabase-js@2";

import { sendReminderEmail } from "../_shared/reminder_email.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST")
    return json({ ok: false, error: "Method not allowed." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader)
      return json({ ok: false, error: "No login session." }, 401);

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user: authUser },
      error: authError,
    } = await callerClient.auth.getUser();
    if (authError || !authUser?.email) {
      return json(
        { ok: false, error: "Invalid session. Please log in again." },
        401,
      );
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const callerNik = authUser.email.replace("@sicatat.local", "");
    const { data: callerProfile, error: callerError } = await admin
      .from("app_user")
      .select("id,role,site_id,is_active")
      .eq("nik", callerNik)
      .single();
    const reminderRoles = new Set(["admin", "supervisor_smg", "foreman_lv"]);
    if (
      callerError ||
      !callerProfile ||
      !callerProfile.is_active ||
      !reminderRoles.has(callerProfile.role)
    ) {
      return json(
        {
          ok: false,
          error: "Your role is not allowed to send reminder emails.",
        },
        403,
      );
    }

    const body = await req.json().catch(() => ({}));
    const reminderId = String(body.reminder_id ?? "").trim();
    if (!reminderId)
      return json({ ok: false, error: "Reminder ID is required." }, 400);

    const { data: reminder, error: reminderError } = await admin
      .from("operational_reminder")
      .select(
        "id,site_id,title,due_date,recipient_emails,category,asset_code,description,priority,assigned_to,location,reminder_schedule,custom_reminder_days,reminder_offsets_days,status,site:site_id(name,code)",
      )
      .eq("id", reminderId)
      .single();
    if (reminderError || !reminder)
      return json({ ok: false, error: "Reminder was not found." }, 404);
    if (reminder.status !== "open") {
      return json(
        { ok: false, error: "Only open reminders can be emailed." },
        409,
      );
    }

    const { data: delivery, error: deliveryError } = await admin
      .from("operational_reminder_delivery")
      .insert({
        reminder_id: reminder.id,
        delivery_type: "manual",
        due_date_snapshot: reminder.due_date,
        recipients: reminder.recipient_emails,
        sent_by: callerProfile.id,
        status: "sending",
      })
      .select("id")
      .single();
    if (deliveryError || !delivery)
      throw new Error("Unable to create email delivery record.");

    try {
      const result = await sendReminderEmail(reminder);
      await admin
        .from("operational_reminder_delivery")
        .update({
          status: "sent",
          provider_id: result.providerId,
          recipients: result.recipients,
          sent_at: new Date().toISOString(),
          error_message: null,
        })
        .eq("id", delivery.id);
      await admin
        .from("operational_reminder")
        .update({ last_sent_at: new Date().toISOString() })
        .eq("id", reminder.id);
      await admin.from("operational_reminder_activity").insert({
        reminder_id: reminder.id,
        action: "email_sent",
        note:
          "Manual email sent to " + result.recipients.length + " recipient(s).",
        details: { delivery_id: delivery.id, delivery_type: "manual" },
        actor_id: callerProfile.id,
      });
      return json({
        ok: true,
        provider_id: result.providerId,
        recipient_count: result.recipients.length,
      });
    } catch (error) {
      const message =
        error instanceof Error
          ? error.message
          : "Unable to send the reminder email.";
      await admin
        .from("operational_reminder_delivery")
        .update({ status: "failed", error_message: message })
        .eq("id", delivery.id);
      throw error;
    }
  } catch (error) {
    console.error(error);
    return json(
      {
        ok: false,
        error:
          error instanceof Error
            ? error.message
            : "Unable to send the reminder email.",
      },
      500,
    );
  }
});
