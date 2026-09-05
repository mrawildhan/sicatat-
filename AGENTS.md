# SICATAT — Codex Handoff

## AI live diagnostic — 2026-09-05

- Canonical source remains worktree `42e3`; do not release stale `284f`.
- Deployed backend `ask-technical-documents` now safely classifies Google errors without exposing raw provider responses or secrets. Model candidates are bounded and checked against the model list; Flash-Lite 3.1/3.5 precede legacy 2.5 candidates.
- REAL signed-in website demo of sandblasting question FAILED: legacy 2.5 candidates returned 404; Flash-Lite request returned 403 with Google's project-denied message, displayed as `PROJECT_ACCESS_DENIED`. AI is NOT verified working. Owner must resolve Google project access; do not claim billing or retries fix it. Billing was not enabled.
- Backend applies to both web and Android callers. No Flutter/UI release this diagnostic. Web remains 2.6.5; last confirmed published Android remains 2.6.4 (2.6.5 APK upload had failed). Do not claim mobile 2.6.5 is available.
- Backend regression test: `node supabase/functions/ask-technical-documents/diagnostics.test.mjs` (Node 24).

This is the active handoff file for Codex. Follow it before editing.

## Current product and non-negotiable rules

- Active app: `flutter_app/` (Flutter/Dart). The JavaScript/Capacitor files in the repository root are historical only.
- Backend: Supabase Auth + PostgreSQL. Keep NIK/PIN login and session restore.
- The product is **online-only**. SQLite in `flutter_app/lib/data/local/` is cache/sync queue only; do not turn it into an offline-first product.
- Never put a Supabase service-role key in Flutter/Dart, APK, docs, or Git. Only the server-side edge function may use it.
- Preserve the duplicate-sheet rule: one `module + date + shift` sheet globally, enforced in Flutter and the Supabase trigger.
- Keep Android Back navigation inside the app; use `AppBackScope` / `AppBackButton` for new top-level pages.
- Temperature safety: 60–69°C is warning/orange, >=70°C critical/red. Values outside -50..250°C require explicit anomaly confirmation and note.
- Verified sheets must remain locked; use the Verify/Return/revision workflow and audit trail.

## Source rilis tunggal — wajib untuk setiap chat

- Sumber rilis yang telah diverifikasi adalah `origin/master`, dengan versi `2.6.5+10265` di `flutter_app/pubspec.yaml` dan `2.6.5` di `AppConfig.appVersion` (dirilis 2026-09-04). Worktree `C:\Users\ASUS\.codex\worktrees\42e3\sicatat` adalah checkout yang digunakan untuk rilis ini.
- Sebelum mengubah, membangun, atau menerbitkan apa pun: baca kedua penanda versi tersebut, periksa `git status`, dan bandingkan dengan versi aplikasi Android serta website yang sedang rilis. Pertahankan seluruh perubahan pengguna yang sudah ada.
- Worktree `C:\Users\ASUS\.codex\worktrees\284f\sicatat` dan salinan utama `D:\Arutmin\Project\sicatat` pernah bertanda `2.5.4+10254`; keduanya **dilarang** dipakai untuk build atau deploy sampai telah ditarik dan diverifikasi sama dengan `origin/master`.
- Bila sebuah chat dibuka pada source lama, hentikan proses rilis. Tarik `origin/master` dan verifikasi versi rilis terlebih dahulu; jangan menghapus, menggantikan, atau membangun ulang fitur berdasarkan source lama.
- Jangan pernah menerbitkan website atau Android dari versi yang lebih rendah daripada baseline rilis. Setiap perubahan fungsional harus dikerjakan dari source rilis tunggal, diverifikasi dengan `flutter analyze` dan `flutter test`, lalu diperbarui di website dan Android sesuai prosedur rilis.

## Fast start

```powershell
Set-Location D:\Arutmin\Project\sicatat\flutter_app
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

For this workspace, the latest Android artifact is `flutter_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (v2.1.2+212). Build output is intentionally ignored by Git.

## Source map

| Area | Primary location |
|---|---|
| App routes and navigation | `flutter_app/lib/app.dart`, `flutter_app/lib/core/widgets/app_navigation.dart` |
| Supabase config | `flutter_app/lib/core/config/app_config.dart` |
| Authentication/current user | `flutter_app/lib/features/auth/` |
| Sheet creation/list/summary | `flutter_app/lib/features/sheets/presentation/` |
| Temperature entry + thresholds | `flutter_app/lib/features/temperature/presentation/temperature_form_screen.dart`, `flutter_app/lib/data/models/master_data_models.dart` |
| Local database/sync queue | `flutter_app/lib/data/local/local_database.dart`, `flutter_app/lib/data/sync/sync_service.dart` |
| Supabase repository | `flutter_app/lib/data/repositories/supabase_sicatat_repository.dart` |
| PDF/CSV exports | `flutter_app/lib/features/reports/presentation/`, `flutter_app/lib/data/reports/report_export_service.dart` |
| Admin user screen | `flutter_app/lib/features/users/presentation/user_management_screen.dart` |
| Database schema/migrations | `supabase/schema.sql`, `supabase/migrations/` |
| Admin account creation edge function | `supabase/functions/create-crew-user/index.ts` |
| Full product/recovery specification | `docs/PRD-SICATAT-v0.5.md` |

## Current UX behavior

- Temperature flow has four default steps: Breaker R1, Sizer R1, Breaker R2, Sizer R2.
- Round time is set automatically at the first saved entry; inspection date is selected only when a sheet is created.
- Incomplete fields can be skipped while drafting. The Sheet Summary card for an incomplete group is red and opens the first missing entry. Complete cards open their per-entry detail in a bottom sheet.
- The default Sheet Summary is deliberately compact: four cards, contributor count, export icon, and sticky Submit. Audit/review/override/delete actions sit in `More options & history`.
- Add User uses a dedicated create-mode state; it calls the `create-crew-user` edge function. If saving a new user fails after deployment, verify that function is deployed and that the signed-in caller is an active `admin`.
- PDF displays 60–69°C orange and >=70°C red. CSV cannot encode colors, so it contains a `Temperature Alert` column with `HIGH 60-69°C` or `CRITICAL >=70°C`.

## Supabase deployment checklist

1. Apply `supabase/schema.sql` to a new project, then every migration in chronological order.
2. Confirm these migrations are present in production: `20260819_prevent_duplicate_shift_sheets.sql` and `20260820_verified_sheet_lock.sql`.
3. Deploy the user-creation function when needed:

```powershell
supabase functions deploy create-crew-user
```

4. Ensure the caller has an active `app_user` row with `role = 'admin'`.
5. Audit RLS by logging in as crew, foreman, supervisor, and admin before a production rollout.

## Required verification before handoff

Run `flutter analyze` and `flutter test`. For meaningful functional changes, test on Android:

1. Login as crew/admin; use Android Back from sheets, forms, admin, and reports.
2. Create a dated Shift Pagi or Malam sheet; make draft input, reopen it, and fill Round 2.
3. Leave entries missing; confirm red summary card returns to the missing input.
4. Check duplicate date+shift+module creation is rejected from a second account.
5. Submit, reopen before verification, then verify/return as a reviewer.
6. Export values 59, 60, 69, 70°C; inspect PDF colours and CSV `Temperature Alert` values.
7. As admin, open User Management, tap Add User, create a test account, and confirm its login.

## Current limits / next safe work

- New equipment and measurement points are master-data driven, but a wholly new temperature section/module still needs a generic form-builder extension.
- iOS distribution needs macOS, Xcode, an Apple Developer account, signing, and TestFlight; it cannot be built/released from Windows alone.
- Reminders remain admin-only and are not yet a guaranteed push/scheduler workflow.
- Do not commit `tmp/`, `build/`, `.dart_tool/`, APK files, Supabase local state, or machine-local Codex settings.
