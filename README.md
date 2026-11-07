
# My Finance

A comprehensive personal finance management application built with Flutter.

## Project Overview

My Finance is designed to manage personal finances, accounts, transactions, assets, savings, loans, budgets, and financial reports from one place.

The project uses a shared Flutter codebase for Android and Windows, with plans for iOS and other desktop platforms.

## Platforms

- Android
- Windows Desktop
- iOS (planned)
- macOS and Linux (planned)

## Core Features

### 1. Dashboard
- Total account balance
- Income and expense summary
- Recent transactions
- Financial overview

### 2. Account Management
- Cash accounts
- Bank accounts
- Savings and current accounts
- Credit and debit cards
- Digital and mobile wallets
- Investment accounts
- Fixed deposits
- Foreign currency accounts
- Custom account types
- Custom account icons
- Opening balances
- Optional account numbers
- Exclude accounts from total balance

### 3. Transactions
- Income
- Expenses
- Own-account transfers
- Transaction history
- Multiple transaction categories
- Transaction attachments

### 4. Loans and Receivables
- Record money lent to other people
- Borrower details
- Loan dates and due dates
- Partial and full repayments
- Outstanding balance tracking

### 5. Assets Management
- Add and manage assets
- Record asset purchases and sales
- Link assets to accounts
- Track asset value
- Depreciation
- Profit and loss calculations

### 6. Savings Goals
- Multiple savings goals
- Target amounts and dates
- Linked accounts
- Contributions and progress tracking
- Completion notifications

### 7. Budget Management
- Monthly and custom budgets
- Category-based spending limits
- Budget progress tracking
- Spending alerts

### 8. Recurring Transactions
- Daily, weekly, monthly and yearly schedules
- Income and expense schedules
- Transfer schedules
- Pause, resume and cancel options
- Automatic transaction processing

### 9. Multi-Currency Support
- PKR
- USD
- GBP
- EUR
- AED
- SAR
- Custom currencies
- Automatic and manual exchange rates
- Historical transaction exchange rates
- PKR consolidated reports

### 10. Attachments
- Camera photos
- Gallery photos
- Multiple photos per transaction
- PDF documents
- Attachment preview and management
- Cloud backup of original files

### 11. Reports and Analytics
- Income reports
- Expense reports
- Account reports
- Asset reports
- Loan reports
- Savings reports
- Budget reports
- Charts and financial summaries

### 12. Firebase Cloud Services
- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Automatic background synchronization
- Manual Sync Now
- Automatic and manual backup
- Restore financial data and attachments
- Offline data support

### 13. Security
- PIN lock
- Biometric authentication
- Face ID and Touch ID support where available
- Android biometric authentication
- Encrypted local data

### 14. Multiple Languages
- Urdu (RTL)
- English (LTR)
- Arabic (RTL)
- Hindi (LTR)
- Language selection in settings

## Technology Stack

- Flutter
- Dart
- SQLite
- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Flutter Local Notifications
- Material Design 3

## Current Development Status

The project is under active development.

The current starter implementation includes:

- Flutter application structure
- SQLite local database
- Basic dashboard
- Account creation
- Income and expense transactions
- Own-account transfers
- Basic account balance updates

Other listed features are planned requirements and will be implemented in subsequent development stages. They should not be considered completed until their code and testing are finished.

## Getting Started

### Requirements

- Flutter SDK
- Dart SDK
- Android Studio or compatible Android build environment
- Git

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

### Run on Windows

```bash
flutter run -d windows
```

### Build Windows Application

```bash
flutter build windows --release
```

## Database

The current implementation uses SQLite for local financial data.

Firebase integration will provide cloud synchronization, backup, and attachment storage in later development stages.

## Repository

GitHub:
https://github.com/shahidlaashary/my-finance-android

## License

Private personal finance project.

All rights reserved.
