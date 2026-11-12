# lib/ architecture

Feature-first Flutter structure designed for one shared Android, iOS, Windows and macOS codebase.

- `main.dart`: application entry point and composition; legacy screen responsibilities will be extracted incrementally.
- `core/database/finance_database.dart`: central `FinanceDB` implementation, extracted from `main.dart` without changing its schema or database version.
- `app/`: app composition, navigation and responsive layout.
- `core/`: cross-feature infrastructure such as database platform selection, platform capabilities, security, files, notifications, startup and theme.
- `features/`: feature-owned screens, models and services.
- `shared/`: reusable UI, common models and utilities.

## Current foundations

- `app/responsive/breakpoints.dart`: shared compact, medium and expanded layout thresholds.
- `core/platform/platform_capabilities.dart`: platform grouping without importing `dart:io`.
- `core/database/database_platform.dart`: keeps desktop SQLite FFI setup out of `main.dart`; Android and iOS retain native sqflite.
- `core/database/finance_database.dart`: owns the existing database class and initialization logic.

Use package imports (`package:my_finance/...`) for Dart files so file moves do not break relative paths. Keep platform/plugin calls behind core services and avoid platform checks scattered through feature screens.

Current modules: finance, vehicles, documents, backup_restore and security.

See [Cross-platform architecture](../docs/CROSS_PLATFORM_ARCHITECTURE.md) for target boundaries, native project strategy and data-safety rules. During development, test records are disposable and schema changes may be made when required. Production data-preservation rules begin when the app is declared complete.
