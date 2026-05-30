import 'dart:js_interop';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

web.BroadcastChannel? _authChannel;

void clearAuthCallbackFragment() {
  web.window.history.replaceState(null, '', '/');
}

// Sets up two cross-tab sync mechanisms:
//  1. BroadcastChannel — the magic link window explicitly posts the session JSON
//     to all other same-origin windows the moment auth fires. Most reliable.
//  2. storage event fallback — catches any window that missed the broadcast
//     (e.g. opened after the magic link was already processed).
void setupCrossTabSync() {
  _authChannel = web.BroadcastChannel('xene_auth_sync');

  _authChannel!.onmessage = ((JSObject obj) {
    final e = obj as web.MessageEvent;
    final data = e.data.dartify();
    if (data is! String || data.isEmpty) return;
    final current = Supabase.instance.client.auth.currentUser;
    if (current != null && !current.isAnonymous) return;
    Supabase.instance.client.auth.recoverSession(data).ignore();
  }).toJS;

  web.window.onstorage = ((JSObject obj) {
    final e = obj as web.StorageEvent;
    final key = e.key;
    if (key == null || !key.contains('auth-token')) return;
    final newValue = e.newValue;
    if (newValue == null || newValue.isEmpty) return;
    Supabase.instance.client.auth.recoverSession(newValue).ignore();
  }).toJS;
}

// Called by the window that just signed in (magic link window). Posts the
// session JSON to all other open windows on the same origin.
void broadcastSession(String sessionJson) {
  if (sessionJson.isEmpty) return;
  (_authChannel ?? web.BroadcastChannel('xene_auth_sync')).postMessage(
    sessionJson.toJS,
  );
}

// Called on AppLifecycleState.resumed — re-reads localStorage as a last-resort
// fallback for browsers that don't propagate storage events cross-process.
Future<void> recoverSessionIfNeeded() async {
  final current = Supabase.instance.client.auth.currentUser;
  if (current != null && !current.isAnonymous) return;
  final storage = web.window.localStorage;
  final len = storage.length;
  for (var i = 0; i < len; i++) {
    final key = storage.key(i);
    if (key == null) continue;
    if (!key.startsWith('sb-') || !key.endsWith('-auth-token')) continue;
    final value = storage.getItem(key);
    if (value == null || value.isEmpty) continue;
    try {
      await Supabase.instance.client.auth.recoverSession(value);
    } catch (_) {}
    return;
  }
}
