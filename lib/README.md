# Application Architecture

This directory contains the Flutter application source code, organized by application layer and feature domain.

## Project Structure

- `main.dart` — application entry point and startup initialization.
- `app/` — root app configuration, navigation shell, app-level screens and responsive layout.
- `core/` — shared infrastructure such as database access, localization, platform capabilities, security, attachments, preferences, startup and theme.
- `features/` — feature-owned screens and services grouped by domain.
- `shared/` — reusable widgets and UI helpers.

## App Layer

- `app/my_finance_app.dart` — root Material application, routes, theme and app-lock gate.
- `app/screens/main_screen.dart` — primary bottom navigation and central create-action sheet.
- `app/screens/more_features_page.dart` — secondary feature navigation.
- `app/screens/more_features_screen.dart` — settings and appearance entry points.

## Feature Modules

- `features/dashboard/` — home dashboard and financial snapshot.
- `features/finance/` — wallets, transactions, categories, loans, parties, assets, budgets, goals, recurring schedules, statistics, reports, exchange rates and WhatsApp automation UI.
- `features/space/` — My Space screens and local content services, including Books, Deals, Docs, Music, Photo, Projects and Video.
- `features/notifications/` — reminders and local notification scheduling.
- `features/search/` — global record search.
- `features/recycle_bin/` — supported deleted-record archive and restore flows.
- `features/backup_restore/` — Backup & Restore information screen; actual backup and restore are disabled during testing.
- `features/staff/` — staff profiles, attendance and salary records.
- `features/stock/` — stock and inventory management.
- `features/vehicles/` — vehicle records, fuel, expenses and related reports.
- `features/installments/` — installment contracts and payments.
- `features/committee/` — committee cycles, members, installments and payouts.
- `features/partners/` — partner profiles and linked financial records.
- `features/security/` — app-lock user interface and security flows.
- `features/settings/` — language, base currency, general preferences and sound settings.

## Core Foundations

- `core/database/` — local SQLite database and database platform setup.
- `core/platform/` — platform capability abstractions.
- `core/security/` — secure local app-lock and installation-related services.
- `core/services/` — shared attachment and app-refresh services.
- `core/preferences/` — local preferences and sound/language settings.
- `core/startup/` — startup initialization and coordination.
- `core/theme/` — application appearance and theme settings.

## Data and Platform Boundaries

- Android is the active development and APK testing target.
- Financial records are stored locally using SQLite.
- My Space has a separate local content database and app-managed file storage.
- Cloud synchronization is not currently a complete production feature.
- Backup and Restore are disabled during testing; test data is disposable.
- Use package imports (`package:my_finance/...`) to keep file references stable.
- Keep platform/plugin interactions within appropriate core services where practical.

See the repository [README](../README.md) for the current feature inventory, limitations, setup instructions and platform status.
