# Application Architecture

This directory contains the Flutter application source code, organized into application infrastructure, domain modules and app-wide features.

## Project Structure

- `main.dart` — application entry point and startup initialization.
- `app/` — root app configuration, navigation shell, app-level screens and responsive layout.
- `core/` — shared infrastructure such as database access, localization, platform capabilities, security, attachments, preferences, startup and theme.
- `modules/` — independent business/domain areas with their own screens, models and services.
- `features/` — app-wide capabilities used across modules or throughout the application.
- `shared/` — reusable widgets and UI helpers.

## Domain Modules

- `modules/finance/` — wallets, transactions, categories, loans, assets, budgets, goals, recurring schedules, statistics, reports, exchange rates and WhatsApp automation.
- `modules/parties/` — centralized party management and party records shared by Finance and other current or future modules.
- `modules/committee/` — committee cycles, members, installments and payouts.
- `modules/installments/` — installment contracts and payments.
- `modules/partners/` — partner profiles and linked financial records.
- `modules/space/` — My Space screens and local content services, including Books, Docs, Music, Photo, Video and the Work area (Agreements).
- `modules/staff/` — staff profiles, attendance and salary records.
- `modules/stock/` — stock and inventory management.
- `modules/vehicles/` — vehicle records, fuel, expenses and related reports.

The Parties module is the shared source for party-management screens and party operations. Other modules should integrate with it rather than creating separate party records or duplicate party-management systems.

## App-wide Features

- `features/dashboard/` — home dashboard and financial snapshot.
- `features/backup_restore/` — Backup & Restore information screen; actual backup and restore are disabled during testing.
- `features/notifications/` — reminders and local notification scheduling.
- `features/recycle_bin/` — supported deleted-record archive and restore flows.
- `features/search/` — global record search.
- `features/security/` — app-lock user interface and security flows.
- `features/settings/` — language, base currency, general preferences and sound settings.

## App Layer

- `app/my_finance_app.dart` — root Material application, routes, theme and app-lock gate.
- `app/screens/main_screen.dart` — primary bottom navigation and central create-action sheet.
- `app/screens/modules_tools_page.dart` — Modules & Tools navigation.
- `app/screens/app_settings_screen.dart` — settings and appearance entry points.

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
