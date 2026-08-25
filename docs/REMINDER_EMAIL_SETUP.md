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
2. Add/select email recipients by ticking the corresponding checkboxes. Use
   **Add another email** to create a new reusable checkbox.
3. Save the reminder, then select **Send email now**.
4. SICATAT confirms delivery only after the email provider accepts the request.

The function is an explicit-send workflow. Automated reminders on the due date
need a separate scheduled job and should be implemented after the team decides
how many days before the due date a notice must be sent.
