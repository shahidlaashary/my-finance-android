import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Is app installation ki stable aur random pehchan.
///
/// Ye hardware identifier nahi. Aik martaba generate hoti hai, secure storage
/// mein save hoti hai aur login ke baghair backend records ko installation-wise alag rakhti hai.
class InstallationIdentityService {
  InstallationIdentityService._();

  static final InstallationIdentityService instance =
      InstallationIdentityService._();

  static const _storageKey = 'my_finance_installation_id_v1';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  String? _installationId;

  /// Secure storage se installation ID load karta hai ya nayi ID generate karta hai.
  Future<void> initialize() async {
    _installationId = await _storage.read(key: _storageKey);
    if (_installationId != null && _installationId!.isNotEmpty) return;

    final id = _createUuidV4();
    await _storage.write(key: _storageKey, value: id);
    _installationId = id;
  }

  /// [initialize] mukammal hone ke baad installation ID return karta hai.
  String get installationId {
    final value = _installationId;
    if (value == null || value.isEmpty) {
      throw StateError(
        'InstallationIdentityService.initialize() must run first.',
      );
    }
    return value;
  }

  String _createUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    // UUID ko RFC 4122 version 4 aur variant format ke mutabiq set karta hai.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}
