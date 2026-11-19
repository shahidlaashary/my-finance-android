# Firebase backend setup (login-free app experience)

This repository now contains the first secure backend scaffold for the
login-free WhatsApp automation feature.

## Why Firebase Anonymous Authentication

The user does not see a login or signup screen. The app silently obtains a
Firebase Anonymous Auth session and uses its UID as the backend installation
identity. This is safer than treating a locally generated installation ID as
authentication. The local random ID remains a separate installation marker;
it is not a credential.

## Required one-time project setup

1. Create a Firebase project owned by the app operator.
2. Register the Android app using the exact application ID from
   `android/app/build.gradle` or `build.gradle.kts`.
3. Enable **Authentication → Sign-in method → Anonymous**.
4. Create the Cloud Firestore database.
5. Install Firebase CLI and Node.js 20 in the deployment environment.
6. Run `firebase login`, then `firebase use --add` to select the project.
7. From `firebase/functions`, run `npm install` and `npm run build`.
8. Deploy Firestore rules and functions with `firebase deploy`.

Do not put Meta access tokens, app secrets or webhook secrets in Flutter assets,
Dart source, Remote Config readable by clients, or Git. Store them in server-side
Secret Manager / Firebase Functions secrets.

## Current backend endpoints

- `getWhatsAppAccount`: reads the authenticated installation's connection
  status and reminder preferences.
- `updateReminderPreferences`: validates boolean settings and refuses to
  enable automation unless that installation has a server-confirmed connected
  WhatsApp number.

Firestore client writes are denied. Only trusted server functions should write
connection records and message history.

## Not yet implemented / deployed

- Flutter Firebase initialization and invisible anonymous sign-in.
- Firebase project-specific Android configuration.
- Meta Embedded Signup, callback/state validation and Cloud API token exchange.
- Meta webhook signature validation.
- Scheduled reminder processing, approved templates, opt-in checks and
  idempotent delivery.
- Production deployment and end-to-end verification.

Until these steps are completed, the app must continue to show WhatsApp as
not connected. Do not manually create a connected record to bypass Meta
verification.
