/// One-time migration: re-encrypt any AES-CBC (v1) tokens in platform_connections
/// to AES-256-GCM (v2). Safe to run multiple times — GCM tokens are skipped.
///
/// Run with:
///   dart run bin/migrate_tokens_gcm.dart
///
/// Requires TOKEN_ENCRYPTION_KEY and SUPABASE_URL + SUPABASE_SERVICE_KEY in env.
/// After a clean run (0 CBC rows remaining), remove _decryptCbcLegacy from
/// lib/src/services/token_store.dart and delete this script.

import 'dart:io';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/token_store.dart';

final _logger = Logger('migrate_tokens_gcm');

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((r) => print('[${r.level.name}] ${r.message}'));

  final db = DatabaseService();
  final store = TokenStore();

  _logger.info('Fetching all platform_connections rows...');

  final rows = await db.client
      .from('platform_connections')
      .select('id, encrypted_token, refresh_token');

  _logger.info(
    'Found ${rows.length} connection(s). Scanning for CBC tokens...',
  );

  int migrated = 0;
  int skipped = 0;
  int errors = 0;

  for (final row in rows) {
    final id = row['id'] as String;
    final encryptedToken = row['encrypted_token'] as String?;
    final refreshToken = row['refresh_token'] as String?;

    final patch = <String, dynamic>{};

    try {
      if (encryptedToken != null && !encryptedToken.startsWith('gcm:')) {
        final plain = store.decryptToken(encryptedToken);
        patch['encrypted_token'] = store.encryptToken(plain);
        _logger.info('  [$id] encrypted_token: CBC → GCM');
      }

      if (refreshToken != null && !refreshToken.startsWith('gcm:')) {
        final plain = store.decryptToken(refreshToken);
        patch['refresh_token'] = store.encryptToken(plain);
        _logger.info('  [$id] refresh_token: CBC → GCM');
      }
    } catch (e) {
      _logger.severe('  [$id] Failed to decrypt — skipping: $e');
      errors++;
      continue;
    }

    if (patch.isEmpty) {
      skipped++;
      continue;
    }

    try {
      await db.client.from('platform_connections').update(patch).eq('id', id);
      migrated++;
    } catch (e) {
      _logger.severe('  [$id] DB update failed: $e');
      errors++;
    }
  }

  _logger.info('');
  _logger.info('Migration complete:');
  _logger.info('  Migrated : $migrated');
  _logger.info('  Skipped  : $skipped (already GCM)');
  _logger.info('  Errors   : $errors');

  if (errors > 0) {
    _logger.warning('Some rows failed — do NOT remove _decryptCbcLegacy yet.');
    exit(1);
  }

  if (migrated == 0) {
    _logger.info(
      'No CBC tokens found — safe to remove _decryptCbcLegacy from token_store.dart.',
    );
  } else {
    _logger.info(
      'All CBC tokens migrated — safe to remove _decryptCbcLegacy from token_store.dart.',
    );
  }

  exit(0);
}
