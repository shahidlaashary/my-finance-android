import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

initializeApp();
const db = getFirestore();

function requireInstallationUid(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "App installation is not authenticated.");
  }
  return uid;
}

const allowedPreferenceKeys = new Set([
  "enabled",
  "beforeDue",
  "onDue",
  "afterDue",
  "paymentConfirmation",
]);

export const getWhatsAppAccount = onCall(async (request) => {
  const uid = requireInstallationUid(request.auth?.uid);
  const ref = db.collection("installations").doc(uid);
  const [installation, connection, preferences] = await Promise.all([
    ref.get(),
    ref.collection("whatsapp").doc("connection").get(),
    ref.collection("preferences").doc("reminders").get(),
  ]);

  return {
    registered: installation.exists,
    connection: connection.exists
      ? {
          status: connection.get("status") ?? "not_connected",
          maskedPhoneNumber: connection.get("maskedPhoneNumber") ?? null,
        }
      : { status: "not_connected", maskedPhoneNumber: null },
    preferences: preferences.exists ? preferences.data() : {
      enabled: false,
      beforeDue: true,
      onDue: true,
      afterDue: true,
      paymentConfirmation: false,
    },
  };
});

export const updateReminderPreferences = onCall(async (request) => {
  const uid = requireInstallationUid(request.auth?.uid);
  const input = request.data as Record<string, unknown> | undefined;
  if (!input || Object.keys(input).length === 0 ||
      Object.keys(input).some((key) => !allowedPreferenceKeys.has(key)) ||
      Object.values(input).some((value) => typeof value !== "boolean")) {
    throw new HttpsError("invalid-argument", "Invalid reminder preferences.");
  }

  const installationRef = db.collection("installations").doc(uid);
  const connection = await installationRef.collection("whatsapp")
    .doc("connection").get();
  if (input.enabled === true && connection.get("status") !== "connected") {
    throw new HttpsError(
      "failed-precondition",
      "Verify a WhatsApp Business number before enabling reminders.",
    );
  }

  await installationRef.set({
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await installationRef.collection("preferences").doc("reminders").set({
    ...input,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  return { saved: true };
});
