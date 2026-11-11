# lib/ architecture

Feature-first Flutter structure. Keep `lib/main.dart` as the application entry point.

- `app/`: app-level composition and feature navigation.
- `core/`: cross-feature infrastructure (security, theme, startup, shared models/services).
- `features/`: feature-owned screens, models and services.
- `shared/`: reusable UI components shared by multiple features.

Feature folders use `screens/`, `models/` and `services/` where applicable. Use package imports (`package:my_finance/...`) for Dart files so file moves do not break relative paths.

Current modules: finance, vehicles, documents, backup_restore and security.

This organization-only refactor does not intentionally change database schema, stored records or application behavior.
