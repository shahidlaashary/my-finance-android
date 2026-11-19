import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stable, random identity for this app installation.
///
/// This is not a hardware identifier. It is generated once, stored in the
/// platform secure storage, and used to keep backend records isolated per
/// installation without requiring an app login.
class InstallationIdentityService {
  InstallationIdentityService._();

  static final InstallationIdentityService instance =
      InstallationIdentityService._();

  static const _storageKey = 'my_finance_installation_id_v1';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  String? _installationId;

  Future<void> initialize() async {
    _installationId = await _storage.read(key: _storageKey);
    if (_installationId != null && _installationId!.isNotEmpty) return;

    final id = _createUuidV4();
    await _storage.write(key: _storageKey, value: id);
    _installationId = id;
  }

  /// Returns the installation ID after [initialize] has completed.
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

    // RFC 4122 version 4 and variant bits.
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
