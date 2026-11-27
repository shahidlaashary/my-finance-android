# My Finance

A local-first personal and business finance manager built with **Flutter**, **Dart** and **SQLite**.

The Android app is the active development and testing target. This README describes the features currently represented by working screens and local services in the repository. A visible screen or configuration option does not necessarily mean that a connected third-party service or production-ready automation is available.

## Project Status

- **Development status:** Active development and testing.
- **Primary platform:** Android.
- **Data model:** Local-first; finance records are stored on the device.
- **Testing data:** Disposable. The current test app is not a production data-preservation release.
- **Release readiness:** Full regression testing, device validation and production hardening remain outstanding.

## Main Navigation

The main bottom navigation currently contains:

1. Home
2. Assets
3. Budgets
4. Goals
5. Loans
6. Stats
7. Txns
8. Wallets

The central **+** action provides shortcuts for creating **Income, Expense, Transfer, Loan, Asset, Budget and Goal** records. Each action opens its corresponding entry form in the shared action sheet.

## Implemented Application Features

### 1. Home Dashboard

- Financial snapshot for assets, receivables and payables.
- Income and expense overview.
- Wallet balance and multi-currency summaries.
- Base-currency consolidated values.
- Overview shortcuts for assets, loans, budgets, goals and recurring transactions.
- Personalized dashboard heading and balance-visibility support.

### 2. Wallets

- Create, edit, archive, restore and delete wallets.
- Multiple wallet types, custom wallet types, icons and currencies.
- Opening balances and live balance updates.
- Manual balance adjustments recorded in transaction history.
- Exclude selected wallets from consolidated totals.
- Wallet-wise transaction history and balance summaries.
- Bank-card style wallet presentation and supported card catalogue data.

### 3. Transactions

- Record Income, Expense and Transfer transactions.
- Transfer between wallets, including different-currency transfers.
- Optional transfer fees.
- Transaction date, time, category, notes and supported attachments.
- Edit, delete and inspect transaction details.
- Transaction filters and wallet balance updates when records are changed.
- Balance-adjustment entries.

### 4. Categories

- Separate income and expense categories.
- Create, edit and delete custom categories.
- Category icons and ordering.
- Category selection in transaction forms and finance views.

### 5. Loans and Parties

- Record **Loan Given** and **Loan Taken**.
- Create and manage party profiles and contact details.
- Link loans to parties.
- Record partial and full repayments.
- Track outstanding amounts, repayment progress and entry history.
- View party ledgers and supported loan attachments.
- Receivable/payable summaries and loan analytics.
- Centralized party management is provided through the separate Parties module and shared by relevant modules.

### 6. Assets

- Add, edit and delete assets.
- Record asset purchases and sales.
- Link supported purchase and sale payments to wallets or loans.
- Update current asset valuation.
- Track purchase value, current value and sale results.
- Manage asset-related repayments and outstanding amounts.
- Asset details, attachments and portfolio analytics.
- Consolidated-balance inclusion control for supported assets.

### 7. Budgets

- Create and manage budgets with category, currency, amount and period.
- Track spending against budget limits.
- View progress and limit indicators.
- Enable, pause and delete budgets.

### 8. Savings Goals

- Create goals with target amounts and dates.
- Optionally link goals to wallets.
- Record contributions and withdrawals.
- Track saved amounts, progress and contribution history.
- View goal totals by currency.

### 9. Recurring Transactions and Schedules

- Create recurring Income, Expense and Transfer schedules.
- Configure frequency, start date and optional end date.
- Pause, resume, edit and delete schedules.
- Add supported attachments to schedules.
- Process due schedules through the app's recurring-transaction service.

### 10. Statistics, Reports and Analytics

- Income, expense and net cash-flow summaries.
- Monthly trends and category breakdowns.
- Wallet and currency-wise summaries.
- Date-range and period filters.
- PDF report export and shareable PDF statements.
- Asset and loan analytics, including status and currency breakdowns.

### 11. Multi-Currency and Exchange Rates

- Assign currencies to wallets and supported finance records.
- Select a base currency for consolidated totals.
- View currency-wise balances without treating different currencies as one amount.
- Refresh exchange rates online where the configured provider is available.
- Manually manage exchange rates and view conversion information.
- Continue using locally saved exchange-rate information when an online refresh is unavailable; rates may become outdated while offline.
- Change wallet currencies with the exchange-rate information required by the currency conversion flow.

#### First-Install Base Currency Selection

- Suggest a base currency during first-time setup using device country signals.
- Detection priority: mobile network country, SIM country, device timezone, then device region/locale.
- Use USD as the fallback when no detected country maps to a supported currency.
- Country detection is designed to work without an internet connection.
- Save the selected base currency after setup; it is not automatically re-detected on subsequent launches.
- Allow the user to select a different base currency manually during setup or later in Settings.

### 12. My Space

My Space is the app's personal file and record area. Its internal sections are:

- **All** — combined view of supported My Space items.
- **Books** — PDF and EPUB books with in-app reading screens.
- **Docs** — document records and related files.
- **Music** — audio files with an in-app audio player.
- **Photo** — image files with an in-app image viewer.
- **Work** — agreements workspace for agreement records, parties, dates, terms and attachments.
- **Video** — video files with an in-app video player.

Additional My Space capabilities include:

- Add files using the device file picker.
- Search and filter supported items.
- Organize supported content using folders, playlists and collections.
- View storage information and manage content.
- Store document details such as category, document number, issue date, expiry date, notes and favorites.
- Add supported document attachments.
- Use the dedicated PDF and EPUB readers.
- Manage agreement records in the Work area.

File extensions currently listed by the My Space import filters:

| Content | Supported extensions |
|---|---|
| Books | PDF, EPUB |
| Music | MP3, M4A, WAV, FLAC |
| Photos | JPG, JPEG, PNG, WEBP, GIF, BMP |
| Videos | MP4, M4V, MOV, MKV, AVI, WEBM, 3GP |

Actual playback or preview may also depend on the Android device and its media/codec support.

### 13. Staff Manager

- Create and manage staff profiles.
- Store contact, job, joining-date and salary details.
- Record salary payments.
- Track attendance.

### 14. Stock Manager

- Create and manage stock items.
- Store item identifiers, categories, units and pricing.
- Record stock movements and quantity adjustments.
- Review item movement history and low-stock information.

### 15. Vehicle Manager

- Manage vehicle profiles and details.
- Record fuel logs, odometer readings and vehicle expenses.
- Track vehicle-related service information and reminders.
- View running costs and cost-per-distance summaries.
- Export supported vehicle reports.

### 16. Installment Manager

- Create installment contracts for supported directions.
- Record payments and payment history.
- Track contract and payment progress.
- Link supported payments to wallets.

### 17. Committee Manager

- Create committees with daily, weekly or monthly cycles.
- Add members and manage turn order.
- Record installments and payouts.
- View schedules, balances, history and member ledgers.
- Optionally link supported installments or payouts to a wallet.

### 18. My Partners

- Create and manage partner profiles.
- Link wallets with a partner.
- Record partner-related transactions.
- Review supported partner transaction history and summaries.

### 19. Properties Manager

- Manage property records and owner information.
- Maintain tenant records.
- Create and manage property contracts.
- Record and manage rent payments.
- Track property maintenance items.
- Review property-related reports and summaries.

### 20. Global Search

- Search supported records across the application.
- Filter results by record type.
- Open matching records and supported details.

### 21. Reminders and Notifications

- Create and manage personal reminders.
- Schedule local device notifications for reminder dates and times.
- Delete reminders and cancel their scheduled notifications.
- Vehicle-related reminders are available in Vehicle Manager.

### 22. Settings, Appearance and Sound

- Configure display name and general app preferences.
- Configure date, week-start and number formats.
- Configure default transaction date and remembered wallet preferences.
- Set the base currency and app language.
- Choose available appearance/theme presets.
- Hide balances on supported screens.
- Configure delete confirmation and haptic feedback.
- Control app sound effects and the app-launch sound through Sound Settings.

### 23. App Lock

- Optional PIN-based app lock.
- PIN secret handling using secure storage and salted hashing.
- Biometric unlock when supported and enrolled on the device.
- Configurable automatic lock timeout.
- Temporary lockout after repeated failed PIN attempts.

### 24. Recycle Bin

- Move supported deleted records into the Recycle Bin.
- Review archived record details.
- Restore supported record types.
- Permanently delete records.

## Limited or Not Yet Production-Ready

The following areas should not be considered complete production integrations:

### WhatsApp

- The app includes a WhatsApp Automation settings screen and reminder options.
- The manual send action opens WhatsApp externally with a prepared message where supported.
- Verified WhatsApp Business account connection and reliable background automatic message delivery are not complete. The screen's connection state should not be treated as proof of an official WhatsApp API connection.

### Backup and Restore

- Backup and Restore are intentionally disabled during the current testing phase.
- The current screen explains that test data is not exported or restored.
- Production-ready local/cloud backup, restore and recovery workflows remain pending.

### Cloud Services and Synchronization

- Firebase packages are present in the dependency configuration, but a complete production cloud account, remote database, file-storage and synchronization workflow is not available.
- Cloud authentication, cloud backup, automatic synchronization and conflict resolution remain future work.

### Localization

- Multiple language options and localization infrastructure are present.
- Complete translation coverage and final language-by-language review remain outstanding.

## Technology Stack

- **Framework:** Flutter
- **Language:** Dart
- **Local database:** SQLite / sqflite
- **Preferences:** Shared Preferences
- **Sensitive local secrets:** Flutter Secure Storage
- **Biometrics:** local_auth
- **Notifications:** Flutter Local Notifications and timezone
- **Files:** File Picker, Image Picker and Path Provider
- **PDF:** PDF generation, viewing and printing utilities
- **Books:** EPUB reader support
- **Audio/video:** audioplayers and video_player

## Data and Testing Notes

- Financial records are stored locally on the device.
- My Space uses its own local content database and app-managed file storage.
- Cloud synchronization is not currently available as a complete feature.
- Backup and Restore are disabled during testing.
- Test data is disposable. Uninstalling or resetting the test app may remove local records and files.
- Do not use a testing build as the only copy of important financial or personal records.

## Getting Started

### Requirements

- Flutter SDK
- Dart SDK compatible with the constraint in `pubspec.yaml`
- Android Studio or another compatible Android build environment
- Git

### Install dependencies

```bash
flutter pub get
```

### Run on Android

```bash
flutter run
```

### Build a release APK

```bash
flutter build apk --release
```

## Automated Tests

The repository includes focused automated tests for selected application services and platform/layout behavior. Test coverage is partial and does not replace full end-to-end testing on physical Android devices.

## Platform Status

- **Android:** active development and APK testing target.
- **iOS, Windows, macOS and Linux:** not yet validated as complete supported releases.

## Repository

https://github.com/shahidlaashary/my-finance-android

## License

Private personal finance project. All rights reserved by Shahid Laashary.
