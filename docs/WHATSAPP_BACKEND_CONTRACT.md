# Login-free WhatsApp automation backend contract

## Product decision

The Finance app remains usable without an account, login or signup. Each app
installation receives a random installation ID, stored in Android/iOS secure
storage. This ID is an app-generated identifier, not a hardware ID and not a
proof of identity.

The installation ID lets the backend keep each installation's WhatsApp
connection, reminder preferences and delivery history separate. It must never
be treated as authentication by itself.

## Required backend security

Before enabling any WhatsApp connection, the backend must exchange the
installation ID for a revocable installation credential. The credential must
be stored only in secure storage and sent over HTTPS. The backend must apply
rate limits, revoke credentials on disconnect, and avoid exposing Meta access
tokens to the app.

For stronger protection, add platform attestation (Play Integrity / App
Attest) and require it during installation registration where supported.
A copied installation ID alone must not grant access to an existing WhatsApp
connection.

## Suggested API contract

All endpoints use HTTPS and JSON. Authenticated endpoints require a short-lived
installation access token in the Authorization header.

- `POST /v1/installations/register`
  - Request: `installation_id`, app version and platform.
  - Response: installation credential and expiry.
  - Re-registration must rotate credentials safely.

- `POST /v1/whatsapp/connection/start`
  - Starts Meta Embedded Signup for the current installation.
  - Response: short-lived signup URL/state. The app opens the Meta flow.

- `GET /v1/whatsapp/connection`
  - Returns only this installation's connection status and masked business
    phone number.

- `POST /v1/whatsapp/connection/callback`
  - Server-side Meta callback processing. Validate state and Meta credentials
    on the server; never trust a client-supplied `connected=true`.

- `DELETE /v1/whatsapp/connection`
  - Revokes this installation's connection and credentials.

- `POST /v1/webhooks/meta/whatsapp`
  - Receives Meta delivery/status events. Verify webhook signatures.

## Automated reminders

A server-side scheduler must process due reminders using each installation's
own settings and WhatsApp connection. It must enforce idempotency so retries
cannot send duplicate messages. Required events:

1. Three days before a payment due date.
2. On the due date.
3. Three days after the due date.
4. Payment confirmation after a payment is recorded, including the updated
   outstanding amount.

Use approved WhatsApp message templates when required by Meta policy. Store
message status and provider message IDs per installation. Do not send if the
installation is disconnected, automation is disabled, the party has no valid
consented WhatsApp destination, or the event was already processed.

## Current implementation boundary

The Flutter app now creates and securely stores a unique random installation
ID at startup. The API server, credential registration, Meta Embedded Signup,
webhooks and scheduled sending are not implemented or deployed yet. The app
must continue to show WhatsApp as not connected until the backend confirms a
real connection.
