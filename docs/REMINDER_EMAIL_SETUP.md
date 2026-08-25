# SICATAT reminder email delivery

The `send-reminder-email` Supabase Edge Function is deployed and is callable
only by an active SICATAT administrator. It sends the saved reminder through
the Gmail API using `arutminreminder@gmail.com` as the sender. The Gmail
OAuth credentials stay only in Supabase and are never included in Flutter or
the APK.

## One-time administrator setup

1. In [Google Cloud Console](https://console.cloud.google.com/), create or
   select a project and enable the **Gmail API**.
2. Configure the OAuth consent screen and add
   `arutminreminder@gmail.com` as a test user while the app is in testing.
3. Create an OAuth client ID for a web application. Obtain a refresh token for
   the mailbox `arutminreminder@gmail.com` with the Gmail send scope:
   `https://www.googleapis.com/auth/gmail.send`.
4. In Supabase Dashboard: **Project Settings → Edge Functions → Secrets**, add:

   - `GMAIL_CLIENT_ID`: Google OAuth client ID.
   - `GMAIL_CLIENT_SECRET`: Google OAuth client secret.
   - `GMAIL_REFRESH_TOKEN`: refresh token authorized by `arutminreminder@gmail.com`.
   - `GMAIL_SENDER_EMAIL`: `arutminreminder@gmail.com`.

The equivalent authenticated CLI command is:

    npx supabase@latest secrets set --project-ref ofczleeyqrxyuuupzirq GMAIL_CLIENT_ID="your-client-id" GMAIL_CLIENT_SECRET="your-client-secret" GMAIL_REFRESH_TOKEN="your-refresh-token" GMAIL_SENDER_EMAIL="arutminreminder@gmail.com"

Do not paste any credential into Flutter source, an APK, Git, or chat. If an
old Resend key was ever exposed, revoke it in Resend; it is not used by this
implementation.

## Operational use

1. Sign in as an active admin and open **Operational reminders**.
2. Add the category, asset/reference, action required, priority, responsible
   person/team, location, due date, and selected recipients.
3. Choose automatic email days: H-30, H-14, H-7, H-1, and/or due date. At
   least one day is required; SICATAT sends selected automatic notices at
   08:00 WITA.
4. Optionally set a repeat interval. When the current task is marked complete,
   SICATAT creates its next month/quarter/semester/year cycle.
5. Select **Send email now** for an immediate, logged delivery; use **Mark
   complete**, **Reopen**, and **History** to manage its lifecycle.

## Automatic scheduler

`dispatch-reminder-emails` is invoked by Supabase Cron every day at 08:00
WITA. It only delivers open reminders whose selected offset matches the due
date, records every delivery attempt, and prevents a duplicate automatic send
for the same reminder, due date, and offset.

The scheduler has a separate secret (`REMINDER_CRON_SECRET`) stored in both
Supabase Edge Function Secrets and Supabase Vault. It is provisioned by the
deployment workflow and must never be copied into Flutter, Git, or chat.
