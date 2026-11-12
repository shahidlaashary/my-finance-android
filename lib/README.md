# lib/ architecture

Feature-first Flutter structure for one shared Android, iOS, Windows and macOS codebase.

- `main.dart`: minimal application entry point; initializes startup services and composes the root app.
- `app/`: root app configuration, navigation shell, app-level screens, theme and responsive layout.
- `core/`: cross-feature infrastructure including database, platform capabilities, security, attachments, refresh notifications, startup and theme.
- `features/`: feature-owned screens, models and services grouped by domain.
- `shared/`: reusable widgets and UI helpers shared across features.

## App layer

- `app/my_finance_app.dart`: root Material application, routes, theme and app-lock gate.
- `app/screens/main_screen.dart`: bottom navigation shell and the central add-transaction action sheet.
- `app/screens/home_screen.dart` is not used; the dashboard belongs to `features/dashboard/screens/home_screen.dart`.
- `app/screens/more_features_page.dart`: More Features navigation page.
- `app/screens/more_features_screen.dart`: settings and appearance screens.
- `app/screens/simple_feature_page.dart`: shared placeholder destination for unfinished feature entries.

## Finance feature

- `features/finance/screens/`: finance screens, including dashboard-independent Assets, Budgets, Categories, Goals, Loans, Transactions and Wallets.
- `features/finance/models/`: finance domain models.
- `features/finance/services/`: finance operations and feature services.
- `features/finance/services/finance_transaction_operations.dart`: transaction database operations used by the add-transaction form.
- `features/finance/screens/transaction_entry_form.dart`: income, expense and transfer entry form.

## Core foundations

- `core/database/finance_database.dart`: central `FinanceDB` implementation; no schema or database-version change is intended by the structural refactor.
- `core/database/database_platform.dart`: desktop SQLite FFI setup; Android and iOS retain native sqflite.
- `core/platform/platform_capabilities.dart`: platform grouping without importing `dart:io`.
- `core/services/`: shared attachment and app-refresh services.
- `core/startup/`: app initialization and startup coordination.

Use package imports (`package:my_finance/...`) for Dart files so file moves do not break paths. Keep platform/plugin calls behind core services and avoid platform checks scattered through feature screens.

Current feature modules include finance, dashboard, vehicles, documents, backup_restore and security.

See [Cross-platform architecture](../docs/CROSS_PLATFORM_ARCHITECTURE.md) for target boundaries, native project strategy and data-safety rules. During development, test records are disposable and schema changes may be made when required. Production data-preservation rules begin when the app is declared complete.
