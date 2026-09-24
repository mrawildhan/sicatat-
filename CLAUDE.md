# SICATAT — Claude Code Handoff

This is the active handoff file for Claude Code. Follow it before editing.

## Current product and non-negotiable rules

- Active app: `flutter_app/` (Flutter/Dart). The JavaScript/Capacitor files in the repository root are historical only.
- Backend: Supabase Auth + PostgreSQL. Keep NIK/PIN login and session restore.
- The product is **online-only**. SQLite in `flutter_app/lib/data/local/` is cache/sync queue only; do not turn it into an offline-first product.
- Never put a Supabase service-role key in Flutter/Dart, APK, docs, or Git. Only the server-side edge function may use it.
- Preserve the duplicate-sheet rule: one `module + date + shift` sheet globally, enforced in Flutter and the Supabase trigger.
- Keep Android Back navigation inside the app; use `AppBackScope` / `AppBackButton` for new top-level pages.
- Temperature safety: 60–69°C is warning, >=70°C critical/red. The warning color differs by surface — the live in-app UI (`temperature_form_screen.dart`) renders it as `AppColors.warning` (amber/yellow, `0xFFF2B84B`), while PDF/CSV exports (`sheet_export_screen.dart`) render it as a genuine orange (`PdfColors.orange300/500/700`) — these are two distinct constants, not the same color reused. `flutter_app/docs/PANDUAN-CREW-SICATAT.md`'s "Kuning" label for this band matches the in-app color; don't treat that as a documentation error. Values outside -50..250°C require explicit anomaly confirmation and note.
- New submissions are final immediately; the sheet creator may explicitly reopen a submitted sheet for revision and resubmit it. Legacy verified sheets remain locked and auditable.

## Fast start

```powershell
Set-Location D:\Arutmin\Project\sicatat\flutter_app
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

Android release APKs land in `flutter_app/build/app/outputs/flutter-apk/` (only `app-arm64-v8a-release.apk` is published, to save Supabase storage). Build output is intentionally ignored by Git, so check `flutter_app/pubspec.yaml` and the active `app_release` row for the current version instead of trusting a number written here.

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
| Gudang (search for everyone; pickups, tool loans, goods receipts for admin/SMG/warehouseman via RPC; stock, pickup history, loans, outstanding PO from the Drive folder "Gudang") | `flutter_app/lib/features/warehouse/`, `supabase/migrations/20260924090000_warehouse_transactions.sql`, `supabase/migrations/20260924100000_warehouse_drive_sources.sql`, `supabase/functions/sync-warehouse-drive/`, `supabase/functions/sync-warehouse-data/` |
| Major Job (admin photo report; Cloudflare D1 + KV, not Supabase) | `flutter_app/lib/features/major_job/`, `cloudflare/major-job/` |
| Full product/recovery specification | `docs/PRD-SICATAT-v0.5.md` |

## Current UX behavior

- Temperature flow has four default steps: Breaker R1, Sizer R1, Breaker R2, Sizer R2.
- Round time is set automatically at the first saved entry; inspection date is selected only when a sheet is created.
- Incomplete fields can be skipped while drafting. The Sheet Summary card for an incomplete group is red and opens the first missing entry. Complete cards open their per-entry detail in a bottom sheet.
- The default Sheet Summary is deliberately compact: four cards, contributor count, export icon, and sticky Submit. Audit/review/override/delete actions sit in `More options & history`.
- Add User uses a dedicated create-mode state; it calls the `create-crew-user` edge function. If saving a new user fails after deployment, verify that function is deployed and that the signed-in caller is an active `admin`.
- PDF displays 60–69°C orange and >=70°C red. CSV cannot encode colors, so it contains a `Peringatan Suhu` column with `TINGGI 60-69°C` or `KRITIS >=70°C` (anomalies without a high reading read `PERLU DITINJAU`). The whole UI, PDF, and CSV are Indonesian since 2026-09-17 ("lembar" for sheet, "shift" for shift — the owner rejected "sif" on 2026-09-17, and "Crew" for crew — the owner replaced "kru" on 2026-09-23); stored database values stay in their original form.

## Suhu menu: three check sheets (2026-09-17)

- Operasional → Suhu opens `/temperature-forms`, which lists **Daily Temperature Feeder Sizer** (the existing `/sheets` flow), **Daily Check Sheet Hydraulic Feeder**, and **Temperature Coal Valve**. Only these three menu names are English (owner request); everything inside the sheets is Indonesian.
- They live in `flutter_app/lib/features/daily_checks/`: `daily_check_forms.dart` defines slots, units, and fields once for the entry screen, summary, and PDF. Hydraulic: Check I/II/III at 10/14/18 (day) or 22/02/06 (night), Feeder 1/2 with Running/Not running/Not accessible, 9 temperatures + 4 pressures + optional speed. Coal valve: 4 time blocks (the Excel form hides its other rows) × Sisi Barat/Timur/Utara/Selatan × RV01–RV04.
- The PDF must look exactly like the owner's Excel forms (`OneDrive - arutmin.com/Wil/Print Daily`). `assets/forms/*.png` are those blank forms exported by Excel itself (US Letter, 220 dpi, logo included); `daily_check_pdf.dart` writes values at cell edges measured from that export. If a form changes, re-export it and re-measure the grid lines (pymupdf `get_drawings`).
- Storage is one table, `daily_check_sheet` (readings in JSONB, one row per form+date+shift+site), migrations `20260917090000` and `20260917091000`. Slots are saved with the `daily_check_save_slot` RPC so two crew members never overwrite each other. Crew can read/write their own team's sheets; submitted sheets are locked by trigger until reopened; only drafts can be deleted.
- Routes: `/daily-checks/:type`, `/new`, `/sheet/:id`, `/sheet/:id/:slot` (`type` = `hydraulic_feeder` | `coal_valve`).

## Review, alerts, and reminders (2026-09-18, v2.8.40)

- Suhu menu is visible to reviewers too (`UserRole.canOpenTemperature` = create or review). The Suhu chooser adds Tren suhu (`/temperature-trend`, fl_chart), and for reviewers Pemantauan & Laporan suhu tinggi, which now include Hydraulic/Coal Valve.
- Daily check sheets have approval ("Mengetahui"): `daily_check_approve(p_id, p_approve)` RPC; `approved_by/approved_at` are only settable through it (trigger + `sicatat.daily_check_approving` setting) and are cleared on reopen. The PDF prints the approver on the signature line.
- Per-point limits: `daily_check_threshold` (admin/SMG, Data master → Batas & peringatan suhu); `DailyCheckThresholds` caches them client-side, default 60/70 °C. Pressure unit is bar.
- Critical alerts: edge function `dispatch-temperature-alerts` (verify_jwt false, `x-reminder-cron-secret`), cron `sicatat-dispatch-temperature-alerts` every 5 min, scans the last 6 h of `daily_check_sheet` and Feeder/Sizer `reading` rows, writes `temperature_alert` (unique `source_key`) and emails `temperature_alert_recipient` via the shared Gmail/Resend `deliverEmail()` in `_shared/reminder_email.ts`. No recipients → status `no_recipient`, nothing sent.
- Check reminders: `check_schedule.dart` computes the 3-3-3 rotation from `roster_anchor` (Pagi team = order[block], Malam = order[(block+2)%3]); Beranda shows `CheckScheduleCard`; Android schedules notifications 10 min before each Hydraulic check for 7 days (`flutter_local_notifications`, inexact alarms, core-library desugaring enabled).
- Critical-temperature phone notifications (v2.8.41, owner chose this over email because crew/foremen have no office email): `critical_alert_watcher.dart` polls `temperature_alert` every 3 min and on resume while the Android app is open; RLS scopes rows to the reviewer. It cannot notify while the app is closed; the owner may later want real push (Firebase Cloud Messaging, needs an owner-created Firebase project).
- App locale is `id_ID` (`flutter_localizations`, `Intl.defaultLocale`).
- APK update offer: `core/services/app_update_prompt.dart` shows "Versi baru tersedia" once per launch on the login screen (before NIK/PIN) or on Beranda after a restored session; Profil → Periksa pembaruan uses the same flow. Anon may read only the active `app_release` row and sign only its APK (migration `20260919090000`). The first phones to see it are those on 2.8.40, when a later version is published.

## Supabase deployment checklist

1. Apply `supabase/schema.sql` to a new project, then every migration in chronological order.
2. Confirm these migrations are present in production: `20260819_prevent_duplicate_shift_sheets.sql`, `20260820_verified_sheet_lock.sql`, and `20260824_normalize_shifts_and_oil_level.sql`.
3. Deploy the user-creation function when needed:

```powershell
supabase functions deploy create-crew-user
```

4. Ensure the caller has an active `app_user` row with `role = 'admin'`.
5. Audit RLS by logging in as crew, foreman, supervisor, and admin before a production rollout.

## Required verification before handoff

Run `flutter analyze` and `flutter test`. For meaningful functional changes, test on Android:

1. Login as crew/admin; use Android Back from sheets, forms, admin, and reports.
2. Create a dated Shift Pagi or Shift Malam sheet ("Lembar baru"); make draft input, reopen it, and fill Round 2.
3. Leave entries missing; confirm red summary card returns to the missing input.
4. Check duplicate date+shift+module creation is rejected from a second account.
5. Submit, confirm the sheet is final immediately, then reopen and resubmit it as its creator to test the revision path.
6. Export values 59, 60, 69, 70°C; inspect PDF colours and CSV `Peringatan Suhu` values.
7. As admin, open User Management, tap Add User, create a test account, and confirm its login.

## Current limits / next safe work

- New equipment and measurement points are master-data driven, but a wholly new temperature section/module still needs a generic form-builder extension.
- iOS distribution needs macOS, Xcode, an Apple Developer account, signing, and TestFlight; it cannot be built/released from Windows alone.
- Reminders remain admin-only and are not yet a guaranteed push/scheduler workflow.
- Do not commit `tmp/`, `build/`, `.dart_tool/`, APK files, Supabase local state, or machine-local Claude settings.
