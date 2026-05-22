import 'dart:async';

/// Short-lived in-memory store for SoundCloud OAuth PKCE nonces.
///
/// Each nonce maps to the initiating user's ID and their PKCE code verifier.
/// Nonces expire after [_kNonceTtl] and are single-use (consumed on callback).
/// A periodic timer purges stale entries so memory does not grow unbounded.

const _kNonceTtl = Duration(minutes: 10);

class _NonceEntry {
  _NonceEntry({required this.userId, required this.codeVerifier})
    : expiry = DateTime.now().toUtc().add(_kNonceTtl);

  final String userId;
  final String codeVerifier;
  final DateTime expiry;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiry);
}

final _store = <String, _NonceEntry>{};
Timer? _cleanupTimer;

/// Store a nonce with its associated userId and codeVerifier.
void storeScNonce(String nonce, String userId, String codeVerifier) {
  _store[nonce] = _NonceEntry(userId: userId, codeVerifier: codeVerifier);
  _cleanupTimer ??= Timer.periodic(
    const Duration(minutes: 5),
    (_) => _purgeExpired(),
  );
}

/// Retrieve and remove a nonce entry. Returns null if not found or expired.
({String userId, String codeVerifier})? consumeScNonce(String nonce) {
  final entry = _store.remove(nonce);
  if (entry == null || entry.isExpired) return null;
  return (userId: entry.userId, codeVerifier: entry.codeVerifier);
}

void _purgeExpired() {
  _store.removeWhere((_, entry) => entry.isExpired);
}
