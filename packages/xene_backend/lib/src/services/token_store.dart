import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:logging/logging.dart';

final _logger = Logger('TokenStore');

/// AES-256-CBC token encryption service.
///
/// Wire format: base64url(iv) : base64(ciphertext)
/// Key source: TOKEN_ENCRYPTION_KEY env var (base64url-encoded 32-byte value).
/// NOTE: This format is NOT compatible with Python's Fernet.
/// Users must re-authenticate when migrating between Python and Dart backends.
class TokenStore {
  Key? _key;

  Key _getKey() {
    if (_key != null) return _key!;
    final raw = Platform.environment['TOKEN_ENCRYPTION_KEY'];
    if (raw == null || raw.isEmpty) {
      throw StateError('TOKEN_ENCRYPTION_KEY must be set');
    }
    final decoded = base64Url.decode(base64Url.normalize(raw));
    final keyBytes = Uint8List(32);
    final copyLen = decoded.length < 32 ? decoded.length : 32;
    keyBytes.setAll(0, decoded.sublist(0, copyLen));
    _key = Key(keyBytes);
    return _key!;
  }

  /// Encrypt a plain-text token. Returns 'ivBase64url:ciphertextBase64'.
  String encryptToken(String token) {
    final key = _getKey();
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = encrypter.encrypt(token, iv: iv);
    final result = '${base64Url.encode(iv.bytes)}:${encrypted.base64}';
    _logger.fine('[token_store] encryptToken: success');
    return result;
  }

  /// Decrypt a token previously produced by [encryptToken].
  String decryptToken(String encryptedToken) {
    final parts = encryptedToken.split(':');
    if (parts.length != 2) {
      throw FormatException(
        'Invalid encrypted token format — expected iv:ciphertext, got $encryptedToken',
      );
    }
    final iv = IV(base64Url.decode(parts[0]));
    final key = _getKey();
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final decrypted = encrypter.decrypt64(parts[1], iv: iv);
    _logger.fine('[token_store] decryptToken: success');
    return decrypted;
  }
}
