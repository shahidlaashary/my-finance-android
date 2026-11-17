# My Finance

A local-first personal and business finance management application built with **Flutter**, **Dart** and **SQLite**.

My Finance brings everyday money management and related personal/business records into one application. The Android application is the current active release target.

## Project Status

The project is actively being developed and tested. The features listed under **Implemented Features** have corresponding screens and service/database logic in the current codebase. This does not mean that the entire application is production-final: broader regression testing, platform validation and the items under **Pending Features** are still outstanding.

## Platforms

- **Android** — current active application and APK build target.
- **Windows, iOS, macOS and Linux** — future platform targets; native project setup and platform-specific validation are not yet complete.

## Implemented Features

### 1. Dashboard and Financial Overview

- Overview of wallet balances and income/expense activity.
- Multi-currency balance summaries and base-currency consolidated values.
- Monthly financial snapshot and net-worth-related overview.
- Quick visibility into assets, loans, budgets, savings goals and recurring transactions.
- Budget threshold indicators and overdue-loan/goal information where applicable.
- Option to hide financial balances across supported screens.

### 2. Wallet Management

- Create, edit and delete wallets.
- Multiple wallet types, custom wallet types, icons and currencies.
- Opening balances and live balance tracking.
- Exclude selected wallets from consolidated totals.
- Wallet management for active and hidden/archived wallets.
- Manual balance adjustment recorded as an adjustment transaction.
- Wallet-wise transaction history and summaries.

### 3. Transactions

- Record Income, Expense and Transfer transactions.
- Transfer money between wallets, including different-currency transfers.
- Optional transfer fee.
- Transaction date, time, category and notes.
- Edit, delete and review transaction history.
- Wallet balances are updated with transaction changes; deleting or editing a transaction reverses/reapplies its balance effect.
- Adjustment entries for wallet balance corrections.
- Attachments for supported transaction records.
- Transaction filters, including All, Income, Expense and Transfer.

### 4. Categories

- Separate Income and Expense categories.
- Add, edit and delete custom categories.
- Category icons and category ordering.
- Category selection in transaction forms and category-based finance views.

### 5. Loans and Repayments

- Record money **Given** and money **Taken**.
- Party profiles with contact details and notes.
- Link loans to the relevant party.
- Record partial and full repayments.
- Track outstanding balances, repayment history and due/overdue status.
- Attach files to supported loan and repayment records.

### 6. Asset Management

- Add, edit and manage assets.
- Record asset purchases and sales.
- Link asset purchases/sales to wallets.
- Update current asset valuation.
- Track purchase value, current value and realized profit/loss.
- Attach images and documents to assets.

### 7. Budgets

- Create and manage budgets with category, currency, amount and period settings.
- Track spending against budget limits.
- View progress and near-limit/exceeded budget indicators.
- Enable, pause and delete budgets.

### 8. Savings Goals

- Create multiple savings goals with target amounts and dates.
- Optionally link goals to wallets.
- Record contributions and withdrawals.
- Track saved amount, target progress and contribution history.
- View savings totals by currency.

### 9. Recurring Transactions

- Create recurring Income, Expense and Transfer schedules.
- Daily, weekly, monthly and yearly frequencies.
- Start and optional end dates.
- Pause, resume, edit and delete schedules.
- Due transactions are processed automatically when the application starts.
- A failed schedule is paused and reported rather than repeatedly retried on every launch.

### 10. Reports and Statistics

- Income, expense and net cash-flow summaries.
- Monthly trends and category breakdowns.
- Wallet balances and wallet-wise summaries.
- Currency-wise reporting.
- Date-range and period filters.
- PDF report export and shareable PDF statements.
- Additional dashboard and statistics views for financial insights.

### 11. Multi-Currency and Exchange Rates

- Currency selection for wallets and financial records.
- Base-currency selection for consolidated totals.
- Online exchange-rate refresh using the configured exchange-rate provider.
- Manual exchange-rate editing.
- Currency conversion and currency-wise summaries.

### 12. Documents and Attachments

- My Documents area for storing document records.
- Document categories, favorites and expiry-date tracking.
- Add files using supported file picker, camera and gallery options.
- Attach images and PDFs to supported records.
- Attachment preview, open, replace and delete actions.
- Shared attachment support for transactions, assets, loans, repayments, savings goals, documents and vehicles where enabled.

### 13. Staff Management

- Create and manage staff profiles.
- Store contact, job, joining-date and salary details.
- Record salary payments.
- Track staff attendance.

### 14. Stock Manager

- Create and manage stock items.
- Store item details such as SKU, category, unit and pricing.
- Record stock movements and quantity adjustments.
- Review item movement history.
- Identify low-stock items.

### 15. Vehicle Manager

- Manage vehicle profiles and details.
- Record fuel logs, odometer readings and vehicle expenses.
- Track vehicle-related reminders and service information.
- View vehicle running costs and cost-per-distance summaries.
- Export vehicle reports to PDF and Excel-compatible workbooks.

### 16. Installment Manager

- Create installment contracts for supported directions.
- Record installment payments and payment history.
- Track contract/payment progress.
- Link payments to wallets so their financial effect is recorded through the wallet transaction flow.

### 17. Committee Manager

- Create committees with daily, weekly or monthly cycles.
- Add members and manage member turn order.
- Record member installments and payouts.
- View committee schedule, balances, history and individual member ledger.
- Optionally link an installment or payout to a personal wallet.

### 18. My Partner

- Create and manage partner profiles.
- Link wallets with a partner.
- Record partner-related transactions.
- Record transfers between linked wallets and partner balances.
- Review partner transaction history and summaries.

### 19. Global Search

- Search saved application records rather than opening a directory of feature/settings cards.
- Search across Transactions, Wallets, Categories, Loans, Budgets, Goals, Assets, Documents, Stock, Staff, Installments, Vehicles and Committee records.
- Filter results by record type.
- Open transaction details and inspect matching record details.

### 20. Reminders and Notifications

- Create and manage personal finance reminders.
- Schedule local device notifications for reminder dates/times.
- Delete reminders and cancel their scheduled notifications.
- Vehicle-related reminders are also available in Vehicle Manager.

### 21. Settings and Personalization

- Save a display name for the dashboard header.
- Configure date format, week start and number format.
- Configure default transaction date and remembered wallet preference.
- Configure delete confirmation and haptic feedback.
- Hide balances on supported screens.
- Choose from the available appearance/theme presets.
- Set the base currency.
- Select a language from the available language list.

### 22. App Lock and Security

- Optional app lock using a 4–8 digit PIN.
- PIN verification uses a salted hash; the PIN itself is stored in secure storage.
- Biometric unlock when supported and enrolled on the device.
- Configurable automatic lock timeout.
- Temporary lockout after repeated failed PIN attempts.

### 23. Recycle Bin

- Move supported deleted records into the Recycle Bin.
- Review archived record details.
- Restore supported records.
- Permanently delete records when they are no longer needed.

## Pending Features

The following items are **not currently implemented as complete application features** and remain planned:

### Cloud and Synchronization

- Firebase Authentication.
- Cloud Firestore data storage.
- Firebase Storage for cloud files and attachments.
- Automatic background synchronization.
- Manual Sync Now.
- Offline-first cloud synchronization and conflict handling.

### Backup and Data Protection

- Backup and Restore are intentionally unavailable during the testing phase.
- Manual backup and restore workflows.
- Cloud backup and restore.
- Production-ready data migration and recovery strategy.
- Encrypted local finance database/data-at-rest protection.

### Localization

- Complete translation coverage for every screen and message in all selectable languages.
- Language-specific formatting and final localization review.

### Financial and Reporting Enhancements

- Historical exchange-rate storage and history reports.
- Further advanced financial reporting and analysis beyond the current reports and statistics.

### Platform Expansion and Release Readiness

- Native Windows, iOS, macOS and Linux project setup.
- Platform-specific build, plugin and device validation.
- Full end-to-end regression testing and production release hardening.

## Technology Stack

- Flutter and Dart.
- SQLite and sqflite for local financial records.
- sqflite_common_ffi / SQLite support for desktop-oriented development.
- Shared Preferences for general local preferences and reminder storage.
- Flutter Secure Storage for sensitive app-lock secrets.
- Flutter Local Notifications for scheduled reminders.
- local_auth for device-supported biometric authentication.
- File Picker, Image Picker and Path Provider for files and attachments.
- PDF generation and sharing utilities.

## Local Data and Testing Notes

- Financial records are currently stored locally on the device.
- Cloud synchronization and remote storage are not available.
- Backup and Restore are disabled during the current testing phase.
- Test data is disposable while the application is under development. Do not treat the current test build as a production data-preservation release.

## Getting Started

### Requirements

- Flutter SDK.
- Dart SDK compatible with the version constraint in pubspec.yaml.
- Android Studio or another compatible Android build environment.
- Git.

### Install Dependencies

```bash
flutter pub get
```

### Run on Android

```bash
flutter run
```

### Build Android APK

```bash
flutter build apk --release
```

## Automated Tests

The repository contains focused automated tests for selected areas, including:

- Transaction and category services.
- Installment and staff services.
- Responsive breakpoints.
- Platform capability handling.

These tests provide partial regression coverage; they do not replace full application/device testing.

## Repository

GitHub: https://github.com/shahidlaashary/my-finance-android

## License

Private personal finance project.

All rights reserved by Shahid Laashary.
