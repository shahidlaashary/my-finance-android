import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:my_finance/core/security/firebase_installation_auth_service.dart';

/// Authenticated client for per-installation WhatsApp settings in Firebase.
///
/// This service deliberately does not expose Meta credentials. The callable
/// functions use the Firebase anonymous-auth identity established at startup.
class WhatsAppBackendService {
  WhatsAppBackendService._();

  static final WhatsAppBackendService instance = WhatsAppBackendService._();

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  bool get isAvailable =>
      Firebase.apps.isNotEmpty &&
      FirebaseInstallationAuthService.instance.isAvailable;

  Future<Map<String, dynamic>> fetchAccount() async {
    _requireAvailable();
    final result = await _functions.httpsCallable('getWhatsAppAccount').call();
    final data = Map<String, dynamic>.from(result.data as Map);
    return data;
  }

  Future<void> updateReminderPreferences(
    Map<String, bool> preferences,
  ) async {
    _requireAvailable();
    if (preferences.isEmpty) {
      throw ArgumentError.value(preferences, 'preferences', 'Must not be empty');
    }
    await _functions
        .httpsCallable('updateReminderPreferences')
        .call<Map<String, dynamic>>(preferences);
  }

  void _requireAvailable() {
    if (!isAvailable) {
      throw StateError(
        'WhatsApp cloud settings are unavailable until Firebase is configured '
        'and this installation is authenticated.',
      );
    }
  }
}
