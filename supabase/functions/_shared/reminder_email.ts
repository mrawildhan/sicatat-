type ReminderEmailSite = { name?: string | null; code?: string | null };

export type ReminderEmailRecord = {
  id: string;
  title: string;
  due_date: string;
  recipient_emails: unknown;
  category?: string | null;
  asset_code?: string | null;
  description?: string | null;
  priority?: string | null;
  assigned_to?: string | null;
  location?: string | null;
  reminder_schedule?: string | null;
  custom_reminder_days?: number | null;
  reminder_offsets_days?: number[] | null;
  site?: ReminderEmailSite | ReminderEmailSite[] | null;
};

export type ReminderEmailResult = {
  providerId: string | null;
  recipients: string[];
};

function escapeHtml(value: string) {
  return value.replace(
    /[&<>"']/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#039;",
      })[character] ?? character,
  );
}

function safeHeader(value: string) {
  return value.replace(/[\r\n]/g, " ").trim();
}

function encodeHeader(value: string) {
  const safe = safeHeader(value);
  if (/^[\x20-\x7E]*$/.test(safe)) return safe;
  const bytes = new TextEncoder().encode(safe);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return "=?UTF-8?B?" + btoa(binary) + "?=";
}

function isValidEmail(value: string) {
  return /^[^\s@<>]+@[^\s@<>]+$/.test(value);
}

function base64UrlEncode(value: string) {
  const bytes = new TextEncoder().encode(value);
  let binary = "";
  const chunkSize = 0x8000;
  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function humanDueDate(value: string) {
  const date = new Date(value + "T00:00:00Z");
  return new Intl.DateTimeFormat("en-GB", {
    day: "2-digit",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  }).format(date);
}

function documentDueDate(value: string) {
  const date = new Date(value + "T00:00:00Z");
  return new Intl.DateTimeFormat("en-GB", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    timeZone: "UTC",
  }).format(date);
}

function textOrDash(value: string | null | undefined) {
  const clean = value?.trim();
  return clean && clean.length > 0 ? clean : "—";
}

function subjectPrefix(priority: string | null | undefined) {
  if (priority === "critical" || priority === "high")
    return "[ACTION REQUIRED]";
  return "[SICATAT REMINDER]";
}

function siteDetails(site: ReminderEmailRecord["site"]) {
  const record = Array.isArray(site) ? site[0] : site;
  const name = textOrDash(record?.name);
  const code = textOrDash(record?.code);
  return { name, code: code === "—" ? null : code };
}

function documentCategory(reminder: ReminderEmailRecord) {
  const description = reminder.description?.toLowerCase() ?? "";
  if (description.includes("vehicle-tax")) return "Taxes";
  if (description.includes("vehicle-stnk")) return "Vehicle registration (STNK)";
  if (description.includes("vehicle-kir")) return "Vehicle roadworthiness (KIR)";
  return textOrDash(reminder.category);
}

function governmentAgency(category: string) {
  if (category === "Taxes" || category.includes("STNK")) {
    return "Samsat Provinsi Kalimantan Selatan";
  }
  if (category.includes("KIR")) return "Dinas Perhubungan";
  return "Not specified";
}

function remarks(value: string | null | undefined) {
  const cleaned = value
    ?.replace(/^Import key:[^.]+\.\s*/i, "")
    .trim();
  return textOrDash(cleaned);
}

function reminderScheduleLabel(reminder: ReminderEmailRecord) {
  switch (reminder.reminder_schedule) {
    case "weekly":
      return "Weekly (7 days before expiry)";
    case "monthly":
      return "Monthly (1 calendar month before expiry)";
    case "custom": {
      const days = reminder.custom_reminder_days;
      return typeof days === "number"
        ? "Custom (" + days + " days before expiry)"
        : "Custom reminder";
    }
    default: {
      const offsets = Array.isArray(reminder.reminder_offsets_days)
        ? reminder.reminder_offsets_days.filter(
            (value): value is number => typeof value === "number",
          )
        : [];
      return offsets.length > 0
        ? "Scheduled (" + offsets.map((days) => days + " days before expiry").join(", ") + ")"
        : "Not specified";
    }
  }
}

function daysUntil(dueDate: string) {
  const todayParts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Makassar",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const part = (type: string) =>
    todayParts.find((item) => item.type === type)?.value ?? "";
  const today = Date.parse(
    part("year") + "-" + part("month") + "-" + part("day") + "T00:00:00Z",
  );
  const due = Date.parse(dueDate + "T00:00:00Z");
  return Math.round((due - today) / 86400000);
}

function urgencyCopy(days: number) {
  if (days < 0) return "OVERDUE";
  if (days === 0) return "DUE TODAY";
  if (days === 1) return "DUE TOMORROW";
  return "DUE IN " + days + " DAYS";
}

async function getGmailAccessToken(
  clientId: string,
  clientSecret: string,
  refreshToken: string,
) {
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: refreshToken,
      grant_type: "refresh_token",
    }),
  });
  const tokenData = await tokenResponse.json().catch(() => ({}));
  if (!tokenResponse.ok || typeof tokenData.access_token !== "string") {
    console.error(
      "Gmail OAuth token request failed",
      tokenResponse.status,
      tokenData.error,
    );
    throw new Error("Gmail authorization is invalid or expired.");
  }
  return tokenData.access_token as string;
}

export async function sendReminderEmail(
  reminder: ReminderEmailRecord,
): Promise<ReminderEmailResult> {
  const gmailClientId = Deno.env.get("GMAIL_CLIENT_ID");
  const gmailClientSecret = Deno.env.get("GMAIL_CLIENT_SECRET");
  const gmailRefreshToken = Deno.env.get("GMAIL_REFRESH_TOKEN");
  const senderEmail = Deno.env.get("GMAIL_SENDER_EMAIL");
  if (
    !gmailClientId ||
    !gmailClientSecret ||
    !gmailRefreshToken ||
    !senderEmail
  ) {
    throw new Error(
      "Email delivery is not configured. Add GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET, GMAIL_REFRESH_TOKEN, and GMAIL_SENDER_EMAIL in Supabase secrets.",
    );
  }

  const storedRecipients = Array.isArray(reminder.recipient_emails)
    ? reminder.recipient_emails
        .filter(
          (email): email is string =>
            typeof email === "string" && isValidEmail(email.trim()),
        )
        .map((email) => email.trim().toLowerCase())
    : [];
  if (storedRecipients.length === 0) {
    throw new Error("This reminder has no valid recipients.");
  }

  // Keep every development and acceptance-test delivery contained to one
  // mailbox. The saved recipient list remains ready for the future live mode.
  const testRecipient = (
    Deno.env.get("REMINDER_TEST_RECIPIENT") ?? "mcasamasam@arutmin.com"
  )
    .trim()
    .toLowerCase();
  if (!isValidEmail(testRecipient)) {
    throw new Error("REMINDER_TEST_RECIPIENT is not a valid email address.");
  }
  const recipients = [testRecipient];

  const title = safeHeader(reminder.title);
  const dueDate = safeHeader(reminder.due_date);
  const category = documentCategory(reminder);
  const agency = governmentAgency(category);
  const documentNumber = textOrDash(reminder.asset_code);
  const documentName = title;
  const documentRemarks = remarks(reminder.description);
  const schedule = reminderScheduleLabel(reminder);
  const attachment = "No attachment";
  const site = siteDetails(reminder.site);
  const humanDue = humanDueDate(dueDate);
  const prefix = subjectPrefix(reminder.priority);
  const dueInDays = daysUntil(dueDate);
  const urgency = urgencyCopy(dueInDays);
  const urgencyColor = dueInDays <= 1 ? "#c2410c" : "#0f766e";
  const html = `
    <div style="margin:0;padding:24px 12px;background:#f4f7f5;font-family:Arial,Helvetica,sans-serif;color:#17221d">
      <div style="max-width:640px;margin:0 auto;background:#ffffff;border:1px solid #dce7e0;border-radius:18px;overflow:hidden">
        <div style="padding:26px 28px;background:#087f23;color:#ffffff">
          <div style="font-size:11px;letter-spacing:.13em;font-weight:700;opacity:.8">SICATAT OPERATIONAL REMINDER</div>
          <h1 style="margin:10px 0 4px;font-size:25px;line-height:1.25">${escapeHtml(title)}</h1>
          <div style="font-size:14px;opacity:.88">${escapeHtml(site.name)}${site.code ? " - " + escapeHtml(site.code) : ""}</div>
        </div>
        <div style="padding:24px 28px">
          <div style="padding:16px 18px;border-radius:12px;background:#eef8f3;border-left:4px solid ${urgencyColor}">
            <div style="font-size:11px;font-weight:700;letter-spacing:.08em;color:${urgencyColor}">${urgency}</div>
            <div style="margin-top:4px;font-size:20px;font-weight:700">${escapeHtml(humanDue)}</div>
          </div>
          <p style="margin:20px 0 14px;font-size:15px;line-height:1.5">Please review the document below and complete the required action before its expiry date.</p>
          <table role="presentation" style="width:100%;border-collapse:collapse;border:1px solid #bed3c5;font-size:14px">
            <tr><th colspan="2" style="padding:10px;background:#087f23;color:#ffffff;font-size:16px;text-align:center">Document details</th></tr>
            <tr><td style="padding:9px 11px;border:1px solid #bed3c5;background:#f4f8f5;font-weight:700;width:38%">Site</td><td style="padding:9px 11px;border:1px solid #bed3c5">${escapeHtml(site.name)}</td></tr>
            <tr><td style="padding:9px 11px;border:1px solid #bed3c5;background:#f4f8f5;font-weight:700">Category</td><td style="padding:9px 11px;border:1px solid #bed3c5">${escapeHtml(category)}</td></tr>
            <tr><td style="padding:9px 11px;border:1px solid #bed3c5;background:#f4f8f5;font-weight:700">Gov. agency</td><td style="padding:9px 11px;border:1px solid #bed3c5">${escapeHtml(agency)}</td></tr>
            <tr><td style="padding:9px 11px;border:1px solid #bed3c5;background:#f4f8f5;font-weight:700">Document number</td><td style="padding:9px 11px;border:1px solid #bed3c5">${escapeHtml(documentNumber)}</td></tr>
            <tr><td style="padding:9px 11px;border:1px solid #bed3c5;background:#f4f8f5;font-weight:700">Document name</td><td style="padding:9px 11px;border:1px solid #bed3c5">${escapeHtml(documentName)}</td></tr>
            <tr><td style="padding:9px 11px;border:1px solid #bed3c5;background:#f4f8f5;font-weight:700">Expired date</td><td style="padding:9px 11px;border:1px solid #bed3c5">${escapeHtml(documentDueDate(dueDate))}</td></tr>
            <tr><td style="padding:9px 11px;border:1px solid #bed3c5;background:#f4f8f5;font-weight:700">Remarks</td><td style="padding:9px 11px;border:1px solid #bed3c5">${escapeHtml(documentRemarks)}</td></tr>
            <tr><td style="padding:9px 11px;border:1px solid #bed3c5;background:#f4f8f5;font-weight:700">Reminder</td><td style="padding:9px 11px;border:1px solid #bed3c5">${escapeHtml(schedule)}</td></tr>
            <tr><td style="padding:9px 11px;border:1px solid #bed3c5;background:#f4f8f5;font-weight:700">Attachment</td><td style="padding:9px 11px;border:1px solid #bed3c5">${escapeHtml(attachment)}</td></tr>
          </table>
          <p style="margin:20px 0 0;font-size:12px;line-height:1.5;color:#6d7a73">This is an automated SICATAT notification. During testing, delivery is routed to the designated test mailbox.</p>
        </div>
      </div>
    </div>`;
  const text = [
    "SICATAT OPERATIONAL REMINDER",
    "",
    title,
    "Site: " + site.name,
    "Due date: " + humanDue,
    urgency,
    "Category: " + category,
    "Gov. agency: " + agency,
    "Document number: " + documentNumber,
    "Document name: " + documentName,
    "Expired date: " + documentDueDate(dueDate),
    "Remarks: " + documentRemarks,
    "Reminder: " + schedule,
    "Attachment: " + attachment,
    "",
    "Please complete the required action and update its status in SICATAT.",
    "Testing mode: delivery is routed to the designated test mailbox.",
  ].join("\n");
  const mime = [
    "From: " + safeHeader(senderEmail),
    "To: " + recipients.join(", "),
    "Subject: " + encodeHeader(prefix + " " + site.name + " - " + title + " - " + urgency.toLowerCase()),
    "MIME-Version: 1.0",
    'Content-Type: multipart/alternative; boundary="sicatat-boundary"',
    "",
    "--sicatat-boundary",
    'Content-Type: text/plain; charset="UTF-8"',
    "Content-Transfer-Encoding: 8bit",
    "",
    text,
    "",
    "--sicatat-boundary",
    'Content-Type: text/html; charset="UTF-8"',
    "Content-Transfer-Encoding: 8bit",
    "",
    html,
    "",
    "--sicatat-boundary--",
  ].join("\r\n");

  const accessToken = await getGmailAccessToken(
    gmailClientId,
    gmailClientSecret,
    gmailRefreshToken,
  );
  const response = await fetch(
    "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
    {
      method: "POST",
      headers: {
        Authorization: "Bearer " + accessToken,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ raw: base64UrlEncode(mime) }),
    },
  );
  const providerData = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error(
      "Gmail API error",
      response.status,
      providerData.error?.status ?? providerData.error,
    );
    throw new Error(
      "Gmail rejected the delivery request. Check the Gmail OAuth configuration.",
    );
  }
  return {
    providerId: typeof providerData.id === "string" ? providerData.id : null,
    recipients,
  };
}
