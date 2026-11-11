import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class GoogleDriveBackupService {
  GoogleDriveBackupService._();

  static const String _driveScope =
      'https://www.googleapis.com/auth/drive.file';

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [_driveScope],
  );

  static Future<String?> connect() async {
    final account = await _googleSignIn.signIn();
    return account?.email;
  }

  static Future<GoogleSignInAccount?> signInSilently() =>
      _googleSignIn.signInSilently();

  static Future<void> disconnect() async {
    await _googleSignIn.signOut();
  }

  static Future<String> uploadBackup({
    required GoogleSignInAccount account,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final authentication = await account.authentication;
    final accessToken = authentication.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Google Drive access token unavailable. Reconnect your Google account.');
    }

    final boundary = 'my-finance-${DateTime.now().microsecondsSinceEpoch}';
    final metadata = jsonEncode({
      'name': fileName,
      'mimeType': 'application/zip',
    });

    final body = BytesBuilder();
    body.add(utf8.encode(
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$metadata\r\n'
      '--$boundary\r\n'
      'Content-Type: application/zip\r\n\r\n',
    ));
    body.add(bytes);
    body.add(utf8.encode('\r\n--$boundary--'));

    final response = await http.post(
      Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files'
        '?uploadType=multipart&fields=id,name',
      ),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body.takeBytes(),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Google Drive upload failed (${response.statusCode}): ${response.body}',
      );
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    return result['id']?.toString() ?? '';
  }
}
