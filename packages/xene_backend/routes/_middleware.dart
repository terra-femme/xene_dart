import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/bandcamp_service.dart';
import 'package:xene_backend/src/services/beatport_service.dart';
import 'package:xene_backend/src/services/discovery_service.dart';
import 'package:xene_backend/src/services/gemini_key_rotator.dart';
import 'package:xene_backend/src/services/press_scout_service.dart';
import 'package:xene_backend/src/services/scheduler_service.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/token_store.dart';
import 'package:xene_backend/src/services/twitch_service.dart';
import 'package:xene_backend/src/services/youtube_service.dart';
import 'package:xene_backend/src/services/discogs_service.dart';

// Wire up the logging package — must run before any route handler.
// Top-level vars in Dart are lazily initialized, so we reference _loggingReady
// inside _debugMiddleware (which runs on every request) to guarantee it fires first.
// The IIFE returns bool so it can be stored as a final variable.
final bool _loggingReady = () {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((r) {
    final prefix = '[${r.level.name}][${r.loggerName}]';
    print('$prefix ${r.message}');
    if (r.error != null) print('$prefix ERROR: ${r.error}');
    if (r.stackTrace != null) print('$prefix STACK: ${r.stackTrace}');
  });
  return true;
}();

// Global singleton instances
final _db = DatabaseService();
final _soundcloud = SoundCloudService(_db);
final _youtube = YouTubeService(_db);
final _beatport = BeatportService(_db);
final _bandcamp = BandcampService(_db);
final _tokenStore = TokenStore();
final _twitch = TwitchService();
final _discogs = DiscogsService();

// Shared Gemini key rotator — one instance for all services so key state is global.
final _geminiRotator = GeminiKeyRotator();

final _pressScout = PressScoutService(_db, rotator: _geminiRotator);

final _discovery = DiscoveryService(
  db: _db,
  soundcloud: _soundcloud,
  discogs: _discogs,
  rotator: _geminiRotator,
);

// Print env key status at server startup — visible before any request.
final bool _envReady = () {
  print('');
  print('══════════════════════════════════════════════════════');
  print('[XENE SERVER STARTUP] Environment check:');
  print('  Gemini keys loaded: ${_geminiRotator.keyCount}');
  print('  LLM discovery: ${_geminiRotator.hasKeys ? "ENABLED ✓ (${_geminiRotator.keyCount} key(s))" : "DISABLED ✗ — set GEMINI_API_KEY"}');
  print('  PRESS_SCOUT_BATCH_SIZE: ${Platform.environment['PRESS_SCOUT_BATCH_SIZE'] ?? '10 (default)'}');
  print('══════════════════════════════════════════════════════');
  print('');
  return true;
}();

final _scheduler = SchedulerService(
  db: _db,
  soundcloud: _soundcloud,
  youtube: _youtube,
  beatport: _beatport,
  bandcamp: _bandcamp,
  pressScout: _pressScout,
)..start();

final middleware = (Handler handler) {
  return handler
      .use(_corsMiddleware)
      .use(_debugMiddleware)
      .use(provider<DatabaseService>((_) => _db))
      .use(provider<SoundCloudService>((_) => _soundcloud))
      .use(provider<YouTubeService>((_) => _youtube))
      .use(provider<BeatportService>((_) => _beatport))
      .use(provider<BandcampService>((_) => _bandcamp))
      .use(provider<SchedulerService>((_) => _scheduler))
      .use(provider<TokenStore>((_) => _tokenStore))
      .use(provider<TwitchService>((_) => _twitch))
      .use(provider<PressScoutService>((_) => _pressScout))
      .use(provider<DiscoveryService>((_) => _discovery))
      .use(provider<DiscogsService>((_) => _discogs))
      .use(provider<GeminiKeyRotator>((_) => _geminiRotator));
};

Handler _corsMiddleware(Handler handler) {
  return (context) async {
    final origin = context.request.headers['origin'] ?? '*';

    // 1. Handle Preflight (OPTIONS)
    if (context.request.method == HttpMethod.options) {
      return Response(
        statusCode: HttpStatus.noContent,
        headers: {
          'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, X-User-Id, Authorization',
          'Access-Control-Max-Age': '86400',
        },
      );
    }

    try {
      // 2. Process request
      final response = await handler(context);
      
      // 3. Add CORS to success/expected responses
      return response.copyWith(
        headers: {
          ...response.headers,
          'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Headers': 'Content-Type, X-User-Id, Authorization',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        },
      );
    } catch (e, stack) {
      // 4. ELI5: If the server "explodes", we still need to send CORS headers.
      // Otherwise, the browser hides the real error behind a "CORS Blocked" message.
      print('[SERVER ERROR] $e');
      print(stack);
      
      return Response.json(
        statusCode: HttpStatus.internalServerError,
        body: {'error': e.toString()},
        headers: {
          'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Headers': 'Content-Type, X-User-Id, Authorization',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        },
      );
    }
  };
}

Handler _debugMiddleware(Handler handler) {
  return (context) async {
    _loggingReady; // triggers lazy init of the logging listener on first request
    _envReady;    // triggers env print on first request if startup didn't fire it
    print('DEBUG: Request path: ${context.request.uri.path}');
    return handler(context);
  };
}
