import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:logging/logging.dart';

final _logger = Logger('TokenStore');

/// AES-256-GCM token encryption service.
///
/// v2 wire format (new):    gcm:base64url(nonce12):base64(ciphertext+tag)
/// v1 wire format (legacy): base64url(iv16):base64(ciphertext)  — read-only, CBC
///
/// GCM provides authenticated encryption: any ciphertext tamper causes decryption
/// to throw, so corrupt or forged tokens are rejected before use.
///
/// Key source: TOKEN_ENCRYPTION_KEY env var (base64url-encoded 32-byte value).
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

  /// Encrypt a plain-text token using AES-256-GCM.
  /// Returns 'gcm:nonceBase64url:ciphertextBase64'.
  String encryptToken(String token) {
    final key = _getKey();
    final iv = IV.fromSecureRandom(12); // 96-bit nonce — GCM recommended size
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    final encrypted = encrypter.encrypt(token, iv: iv);
    final result = 'gcm:${base64Url.encode(iv.bytes)}:${encrypted.base64}';
    _logger.fine('[token_store] encryptToken: gcm success');
    return result;
  }

  /// Decrypt a token. Supports both GCM (v2) and legacy CBC (v1) wire formats.
  String decryptToken(String encryptedToken) {
    final parts = encryptedToken.split(':');
    if (parts.length == 3 && parts[0] == 'gcm') {
      return _decryptGcm(parts[1], parts[2]);
    }
    if (parts.length == 2) {
      return _decryptCbcLegacy(parts[0], parts[1]);
    }
    throw FormatException(
      'Invalid encrypted token format — expected gcm:nonce:ct or iv:ct',
    );
  }

  String _decryptGcm(String nonceB64, String ciphertextB64) {
    final key = _getKey();
    final iv = IV(base64Url.decode(base64Url.normalize(nonceB64)));
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    final decrypted = encrypter.decrypt64(ciphertextB64, iv: iv);
    _logger.fine('[token_store] decryptToken: gcm success');
    return decrypted;
  }

  String _decryptCbcLegacy(String ivB64, String ciphertextB64) {
    final key = _getKey();
    final iv = IV(base64Url.decode(ivB64));
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final decrypted = encrypter.decrypt64(ciphertextB64, iv: iv);
    _logger.fine('[token_store] decryptToken: cbc-legacy success');
    return decrypted;
  }
}
