# Cross-platform architecture

## Goal

Maintain one Flutter application and one shared codebase for Android, iOS,
Windows and macOS. Linux remains a useful development target where the
required plugins support it. Platform folders and build workflows are enabled
only when their native toolchains and plugin support are verified.

## Application layers

- `lib/app/`: application composition, navigation and responsive layout.
- `lib/core/`: infrastructure shared by multiple modules and features,
  including database, platform capabilities, files, security, notifications,
  startup and theme.
- `lib/modules/`: independent business/domain areas. Each module owns its
  screens, models and services where applicable.
- `lib/features/`: app-wide capabilities shared across domain modules.
- `lib/shared/`: reusable UI, common models and utilities.

## Domain modules

The current module structure is:

- `modules/finance/` — wallets, transactions, assets, loans, budgets, goals,
  reports, categories, recurring transactions and exchange rates.
- `modules/parties/` — centralized party management and records reusable by
  Finance, Installments, Committee, Staff, Stock, Vehicles and future modules.
- `modules/committee/`
- `modules/installments/`
- `modules/partners/`
- `modules/space/`
- `modules/staff/`
- `modules/stock/`
- `modules/vehicles/`

A shared domain record should have one authoritative owner. Modules that need
party data should use the Parties module rather than maintaining duplicate
party databases or management screens.

## App-wide features

- `features/dashboard/`
- `features/backup_restore/`
- `features/notifications/`
- `features/recycle_bin/`
- `features/search/`
- `features/security/`
- `features/settings/`

## Platform boundaries

- Use `core/platform/` for platform identification and capability decisions.
- Use `core/database/` to select the correct SQLite implementation.
- Use `core/files/` for shared file and attachment contracts, with native
  adapters only where a platform requires different behavior.
- Keep app-lock/biometric, notification, backup and file-picker integrations
  behind services so feature screens do not own plugin-specific behavior.
- Prefer Flutter's cross-platform APIs and conditional imports when a native
  implementation is genuinely required.
- Do not scatter `dart:io Platform` checks through shared UI or domain logic.

## Responsive application

Use the shared breakpoints in `app/responsive/`. Mobile keeps the existing
navigation and interaction model. Tablet and desktop can progressively adopt
wider content constraints, adaptive navigation, keyboard/mouse support and
resizable-window layouts without duplicating module logic.

## Native projects and builds

The intended Flutter project targets are:

- `android/` — current Android release target.
- `ios/` — add and validate with macOS and Xcode.
- `windows/` — add and validate with the Windows desktop toolchain.
- `macos/` — add and validate with macOS and Xcode.
- `test/` and `integration_test/` — shared and platform regression coverage.

Do not generate native folders by hand. Generate them with Flutter tooling in a
controlled change, then verify each platform's native configuration. Keep the
Android APK workflow Android-only; add separate workflows for iOS, Windows and
macOS when the matching runners and signing requirements are ready.

## Development data and migration policy

During the active development and testing phase, entered records are disposable
test data. Database schema changes, table additions and version updates may be
made when a feature or platform implementation technically requires them.
Explain significant changes and test them before merging.

The production-data protection phase begins only when the product owner
explicitly declares the app complete and in regular use. From that point onward,
every update that can affect stored records must include a reviewed migration,
a backup/restore plan and regression tests. Existing user records must be
preserved unless the product owner explicitly requests otherwise.

## Delivery sequence

1. Audit plugin/platform compatibility and current platform-specific code.
2. Add shared platform, database and responsive foundations.
3. Keep app-wide features separate from business/domain modules.
4. Add native platform projects and dedicated build workflows.
5. Test Android regression first, then validate each additional platform on
   its supported native toolchain.
