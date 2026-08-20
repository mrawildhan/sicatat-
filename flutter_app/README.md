# SICATAT Flutter Migration

Flutter rewrite of the SICATAT field temperature-check app.

## Current migration slice

This first slice establishes the new visual language and navigation shell:

- Login screen with NIK/PIN fields
- Crew dashboard with sync status and quick actions
- Sheet list with Draft, Synced, and Not synced states
- New-sheet flow with date and shift selection
- Material 3 design system optimized for field use

The Supabase schema and existing `sheet → round → unit_status → reading`
domain model remain the source of truth. Data services are isolated behind
repositories so the migration can proceed screen by screen without changing
the backend contract.

## Run

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_ANON_KEY=your_publishable_key
```

The Flutter SDK is required. Android can be built on Windows; iOS builds and
signing require macOS/Xcode.
