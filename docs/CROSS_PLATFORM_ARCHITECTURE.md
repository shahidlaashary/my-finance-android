# Cross-platform architecture

## Goal

Maintain one Flutter application and one shared feature codebase for Android,
iOS, Windows and macOS. Linux remains a useful development target where the
required plugins support it. Platform folders and build workflows are enabled
only when their native toolchains and plugin support are verified.

## Current architectural layers

- `lib/app/`: application composition, navigation and responsive layout. The entry point is now a thin bootstrap that initializes startup services and composes the root app; navigation and feature screens live in their respective app and feature modules.
- `lib/core/`: infrastructure shared by multiple features (database,
  platform capabilities, files, security, notifications, startup and theme).
- `lib/features/`: feature-owned screens, models and services.
- `lib/shared/`: reusable UI, common models and utilities.

## Target feature layout

Each feature owns its presentation, domain models and application services.
As a feature grows, split it into `presentation/`, `domain/` and
`data/` only when that separation is useful; do not create empty layers.

- `features/finance/`
- `features/vehicles/`
- `features/documents/`
- `features/backup_restore/`
- future approved modules: `inventory/`, `business/` and `employees/`

## Platform boundaries

- Use `core/platform/` for platform identification and capability decisions.
- Use `core/database/` to select the correct SQLite implementation.
- Use `core/files/` for shared file and attachment contracts, with native
  adapters only where a platform requires different behavior.
- Keep app-lock/biometric, notification, backup and file-picker integrations
  behind services so feature screens do not own plugin-specific behavior.
- Prefer Flutter's cross-platform APIs and conditional imports when a native
  implementation is genuinely required.
- Do not scatter `dart:io Platform` checks through shared UI or feature logic.

## Responsive application

Use the shared breakpoints in `app/responsive/`. Mobile keeps the existing
navigation and interaction model. Tablet and desktop can progressively adopt
wider content constraints, adaptive navigation, keyboard/mouse support and
resizable-window layouts without duplicating feature logic.

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
3. Move startup, database, file, security and notification responsibilities
   out of feature screens and the large entry-point file incrementally.
4. Add native platform projects and dedicated build workflows.
5. Test Android regression first, then validate each additional platform on
   its supported native toolchain.
