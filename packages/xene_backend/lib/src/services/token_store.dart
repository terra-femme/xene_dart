import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:logging/logging.dart';

final _logger = Logger('TokenStore');

/// AES-256-GCM token encryption service.
///
/// Wire format: gcm:base64url(nonce12):base64(ciphertext+tag)
///
/// GCM provides authenticated encryption: any ciphertext tamper causes decryption
/// to throw, so corrupt or forged tokens are rejected before use.
///
/// Key source: TOKEN_ENCRYPTION_KEY env var (base64url-encoded 32-byte value).
///
/// Legacy CBC (v1) support was removed after bin/migrate_tokens_gcm.dart was run.
/// If decryption fails on old tokens, run the migration script first.
class TokenStore {
  Key? _key;

  Key _getKey() {
    if (_key != null) return _key!;
    final raw = Platform.environment['TOKEN_ENCRYPTION_KEY'];
    if (raw == null || raw.isEmpty) {
      throw StateError('TOKEN_ENCRYPTION_KEY must be set');
    }
    final decoded = base64Url.decode(base64Url.normalize(raw));
    // AES-256 requires exactly 32 key bytes. Previously a short key was silently
    // zero-padded, which would mask a misconfiguration with a dangerously weak
    // key. Fail loudly instead so a bad TOKEN_ENCRYPTION_KEY is caught at startup.
    if (decoded.length != 32) {
      throw StateError(
        'TOKEN_ENCRYPTION_KEY must decode to exactly 32 bytes for AES-256 '
        '(got ${decoded.length}). Generate one with: '
        "dart -e \"import 'dart:math';import 'dart:convert';"
        'void main(){final r=Random.secure();'
        'print(base64Url.encode(List<int>.generate(32,(_)=>r.nextInt(256))));}"',
      );
    }
    _key = Key(Uint8List.fromList(decoded));
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

  /// Decrypt a GCM-encrypted token (gcm:nonce:ciphertext format).
  /// Run bin/migrate_tokens_gcm.dart first if any CBC-format tokens remain in DB.
  String decryptToken(String encryptedToken) {
    final parts = encryptedToken.split(':');
    if (parts.length == 3 && parts[0] == 'gcm') {
      return _decryptGcm(parts[1], parts[2]);
    }
    throw FormatException(
      'Invalid or unsupported token format — expected gcm:nonce:ct. '
      'Run bin/migrate_tokens_gcm.dart to migrate any legacy CBC tokens.',
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
}
