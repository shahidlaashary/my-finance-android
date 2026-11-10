My Finance

A personal & business finance management application built with Flutter and Dart.
My Finance aims to provide a single place to manage Accounts, Attachments, Assets, Budgets, Goals, Loans, Savings, Transaction, Recurring Transactio, Stats and Wallets.

Project Overview

The application uses a shared Flutter codebase with SQLite for local financial data storage.

The project targets Android and Windows Desktop, with plans to support iOS and other desktop platforms.

Platforms

* Android
* Windows Desktop
* iOS (planned)
* macOS (planned)
* Linux (planned)

Features Under Development

1. Dashboard and Accounts

* Account management
* Multiple account types
* Opening balances
* Account balance tracking
* Custom account categories and icons
* Account exclusion from total balance
* Income and expense overview

2. Transactions

* Income and expense records
* Own-account transfers
* Transaction history
* Transaction categories
* Transaction attachments

3. Loans and Repayments

* Record money lent to others
* Borrower details
* Loan dates and due dates
* Partial and full repayments
* Outstanding balance tracking
* Repayment attachments

4. Assets Management

* Add and manage assets
* Record asset purchases and sales
* Link assets to accounts
* Track purchase and current values
* Realized profit and loss tracking

5. Goals Management

* Multiple savings goals
* Target amounts and dates
* Linked accounts
* Contributions and progress tracking

6. Budget Management

* Monthly and custom budgets
* Category-based spending limits
* Budget progress tracking

7. Recurring Transactions

* Daily, weekly, monthly, and yearly schedules
* Income and expense schedules
* Transfer schedules
* Pause, resume, and cancel options
* Automatic processing of due transactions

8. Attachments

* Camera and gallery images
* PDF documents
* Multiple attachments
* Attachment preview and management
* Integration with supported financial records

9. Reports and Analytics

* Income and expense reports
* Account summaries
* Category-based reports
* Financial trends
* Currency-wise summaries

10. Multi-Currency Support

* Currency information associated with accounts
* Currency-wise financial summaries
* Planned currencies include PKR, USD, GBP, EUR, AED, and SAR
* Exchange-rate conversion and consolidated reporting are planned

Technology Stack

* Flutter
* Dart
* SQLite
* sqflite
* Material Design

Current Development Status

The project is under active development.

The current implementation includes development work on:

* Flutter application structure
* SQLite local database
* Account management
* Income and expense transactions
* Own-account transfers
* Transaction categories
* Loans and repayments
* Financial attachments
* Asset management
* Savings goals
* Budget management
* Recurring transactions
* Financial reports and analytics

Features are being reviewed and integrated incrementally. Final completion and testing are still pending.

Planned Features

Firebase and Cloud Services

* Firebase Authentication
* Cloud Firestore
* Firebase Storage
* Automatic background synchronization
* Manual Sync Now
* Cloud backup and restore
* Offline synchronization support

Security

* PIN lock
* Biometric authentication
* Face ID and Touch ID where available
* Android biometric authentication
* Encrypted local financial data

Notifications

* Savings goal notifications
* Budget spending alerts
* Loan due-date reminders
* Recurring transaction reminders

Localization

* Urdu (RTL)
* English (LTR)
* Arabic (RTL)
* Hindi (LTR)
* Language selection in settings

Advanced Financial Features

* Automatic and manual exchange rates
* Historical exchange rates
* PKR consolidated reports
* Advanced asset depreciation
* Additional financial analytics

Getting Started

Requirements

* Flutter SDK
* Dart SDK
* Android Studio or a compatible Android build environment
* Git

Install Dependencies

flutter pub get

Run on Android

flutter run

Build Android APK

flutter build apk --release

Run on Windows:

flutter run -d windows

Build Windows Application

flutter build windows --release

Database:

The application currently uses SQLite for local financial data.

Cloud synchronization, remote backup, and cloud attachment storage are planned for future development.

Repository

GitHub:

https://github.com/shahidlaashary/my-finance-android

License:

Private personal finance project.

All rights reserved by Shahid Laashary
