# Continuation Handoff — SICATAT Flutter

Read [`../CLAUDE.md`](../CLAUDE.md) first. This short file is for a new agent/session.

## Commit target

- Repository: `https://github.com/mrawildhan/sicatat-`
- Active implementation: `flutter_app/`
- Current application release: `2.1.2+212`
- Android trial artifact (not committed): `flutter_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

## Latest completed work

1. Kept Supabase login and online-only gate, while reducing repeated connection false alarms.
2. Completed Breaker/Sizer R1/R2 draft flow, automatic round timestamps, duplicate sheet protection, Verify/Return/audit lock, and threshold/anomaly confirmation.
3. Added admin user creation UI; it requires the `create-crew-user` Supabase Edge Function.
4. Reworked PDF report and CSV safety notices for temperatures at/above 60°C.
5. Changed Sheet Summary default view to a compact four-card matrix. Incomplete cards route to missing input; detailed entries and review/audit actions are on demand.

## Resume prompt for Claude Code

```text
Read CLAUDE.md and docs/PRD-SICATAT-v0.5.md completely. Continue the Flutter app in flutter_app/ only. Preserve Supabase NIK/PIN login, online-only behavior, existing features, the database migrations, and Android Back navigation. First run flutter analyze and flutter test; inspect the working tree before changing anything. Do not touch the historical Capacitor prototype in the repository root unless explicitly requested.
```
