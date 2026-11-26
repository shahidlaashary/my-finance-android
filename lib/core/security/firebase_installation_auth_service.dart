import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// App installation ko Firebase Anonymous Auth ke zariye background mein authenticate karta hai.
///
/// Login ya signup UI nahi dikhata. Firebase project configuration na ho to
/// Finance app local mode mein kaam jari rakhti hai.
class FirebaseInstallationAuthService {
  FirebaseInstallationAuthService._();

  static final FirebaseInstallationAuthService instance =
      FirebaseInstallationAuthService._();

  bool _available = false;
  String? _errorCode;

  bool get isAvailable => _available;
  String? get errorCode => _errorCode;
  String? get installationUid =>
      _available ? FirebaseAuth.instance.currentUser?.uid : null;

  /// Firebase configuration check karke anonymous installation session shuru karta hai.
  Future<void> initialize() async {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const messagingSenderId =
        String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

    if (apiKey.isEmpty ||
        appId.isEmpty ||
        messagingSenderId.isEmpty ||
        projectId.isEmpty) {
      _errorCode = 'firebase_config_missing';
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: apiKey,
            appId: appId,
            messagingSenderId: messagingSenderId,
            projectId: projectId,
          ),
        );
      }

      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
      _available = auth.currentUser != null;
      _errorCode = _available ? null : 'anonymous_auth_unavailable';
    } on FirebaseException catch (error) {
      _available = false;
      _errorCode = error.code;
    } catch (_) {
      _available = false;
      _errorCode = 'firebase_initialization_failed';
    }
  }
}
