# SICATAT reminder email delivery

The send-reminder-email Supabase Edge Function is deployed and is callable
only by an active SICATAT administrator. It sends the selected recipients from
the saved reminder using [Resend](https://resend.com).

## One-time administrator setup

1. Create or sign in to a Resend account and verify the sending domain that
   will be used by SICATAT.
2. Create a Resend API key with permission to send email.
3. In Supabase Dashboard: **Project Settings → Edge Functions → Secrets**, add:

   - RESEND_API_KEY: the API key from Resend.
   - RESEND_FROM_EMAIL: a verified sender, for example
     SICATAT <reminder@your-verified-domain.com>.

The equivalent authenticated CLI command is:

    npx supabase@latest secrets set --project-ref ofczleeyqrxyuuupzirq RESEND_API_KEY="your-resend-key" RESEND_FROM_EMAIL="SICATAT <reminder@your-verified-domain.com>"

Do not paste either value into Flutter source, an APK, Git, or chat.

## Operational use

1. Sign in as an active admin and open **Operational reminders**.
2. Add/select email recipients by ticking the corresponding checkboxes. Use
   **Add another email** to create a new reusable checkbox.
3. Save the reminder, then select **Send email now**.
4. SICATAT confirms delivery only after the email provider accepts the request.

The function is an explicit-send workflow. Automated reminders on the due date
need a separate scheduled job and should be implemented after the team decides
how many days before the due date a notice must be sent.
