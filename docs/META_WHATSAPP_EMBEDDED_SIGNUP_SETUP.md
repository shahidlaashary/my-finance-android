# Meta WhatsApp Business onboarding setup

This checklist is the next external prerequisite for the one-button
`Connect WhatsApp → Verify Number → Connected` experience.

## What the app will do

1. The user taps **Connect WhatsApp**.
2. The app asks the backend to create a short-lived signup session.
3. The app launches Meta's official Embedded Signup flow.
4. The user signs in to Meta, selects or creates a Business Portfolio and
   WhatsApp Business Account, chooses an eligible phone number, and grants
   the requested permissions.
5. Meta returns a short-lived authorization result to the app.
6. The app sends that result and the signup state to the backend.
7. The backend validates the state, exchanges the authorization code using
   server-held credentials, verifies the WABA and phone-number IDs, subscribes
   the app to webhooks, and stores encrypted credentials.
8. The app fetches connection status from the backend and displays
   **Connected** only after server-side verification succeeds.

The app must never receive or store the permanent Meta access token or App
Secret. A client callback alone is not proof of a successful connection.

## Meta developer setup required

The project owner must create/configure these items in Meta:

- A Meta for Developers app with the WhatsApp product enabled.
- A Business Portfolio with the required business verification completed
  where Meta requires it.
- WhatsApp Embedded Signup configured for the app.
- The Embedded Signup configuration ID.
- The Meta App ID.
- The exact Android package name and signing certificate fingerprints for
  the app's supported build variants.
- A verified HTTPS backend domain and HTTPS callback/webhook URLs.
- A public privacy policy and data-deletion instructions URL.
- Required app permissions and any Meta App Review / business verification
  approvals applicable to production use.

Keep the App Secret and any long-lived access token in backend secret
management only. Never add them to Flutter source, assets, remote config,
GitHub, or APK build arguments that are exposed to users.

## Existing WhatsApp Business app numbers

The intended experience is to retain the user's existing WhatsApp Business
app number where Meta's Coexistence flow supports that account and number.
Coexistence is subject to Meta's current eligibility, country, account,
onboarding and policy requirements. It cannot be guaranteed for every
number. If Meta does not offer Coexistence for a user, the app must explain
the available official alternative rather than silently migrating or
disconnecting the number.

The user must explicitly approve Meta's permissions and complete any
verification Meta requires. The app cannot connect a personal or Business
WhatsApp account without that user action.

## Backend endpoints to implement

The backend contract in `WHATSAPP_BACKEND_CONTRACT.md` defines the security
boundary. The implementation must provide:

- `POST /v1/whatsapp/connection/start`: create a one-time state and return
  the approved Meta signup launch configuration.
- `POST /v1/whatsapp/connection/callback`: validate the one-time state and
  exchange the returned authorization code server-side.
- `GET /v1/whatsapp/connection`: return verified status and a masked number.
- `DELETE /v1/whatsapp/connection`: revoke this installation's connection.
- `POST /v1/webhooks/meta/whatsapp`: verify Meta webhook signatures and
  process message delivery/status events.

The state must be single-use, short-lived, bound to the authenticated app
installation, and protected against CSRF/replay. Validate that the WABA and
phone-number IDs belong to the onboarding result before marking connected.

## Production acceptance checks

- A fresh app installation can start signup without an app login screen.
- Two installations cannot read or change each other's WhatsApp connection.
- Closing or cancelling Meta signup leaves the status Not connected.
- Invalid, expired, reused or mismatched state is rejected.
- No client can set its own status to Connected.
- Disconnect revokes backend credentials and stops scheduled messages.
- The number is marked Connected only after backend verification and webhook
  subscription succeed.
- Coexistence is offered only when Meta makes it available for that account.
- Automated reminders are not enabled until connection, consent and message
  template requirements are all satisfied.

## Owner-provided configuration still required

Implementation can be completed against test credentials, but live onboarding
cannot be activated until the owner supplies/configures the Meta App ID,
Embedded Signup configuration ID, backend domain/callbacks, and the Firebase
project deployment settings. Secrets must be entered directly into the
hosting provider's secret manager, not sent in chat or committed to Git.
