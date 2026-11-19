import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Silently authenticates this app installation with Firebase Anonymous Auth.
///
/// No login/signup UI is shown. If Firebase project configuration has not
/// been supplied yet, the Finance app continues working locally.
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
