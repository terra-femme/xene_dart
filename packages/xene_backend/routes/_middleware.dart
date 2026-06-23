import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dio/dio.dart' hide Response;
import 'package:xene_backend/src/utils/auth_utils.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/repositories/publication_repository.dart';
import 'package:xene_backend/src/services/api_analytics_service.dart';
import 'package:xene_backend/src/services/bandcamp_service.dart';
import 'package:xene_backend/src/services/beatport_service.dart';
import 'package:xene_backend/src/services/discovery_service.dart';
import 'package:xene_backend/src/services/gemini_key_rotator.dart';
import 'package:xene_backend/src/services/press_scout_service.dart';
import 'package:xene_backend/src/services/publication_poller_service.dart';
import 'package:xene_backend/src/services/scheduler_service.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/token_store.dart';
import 'package:xene_backend/src/services/twitch_service.dart';
import 'package:xene_backend/src/services/youtube_service.dart';
import 'package:xene_backend/src/services/discogs_service.dart';
import 'package:xene_backend/src/services/analysis_service.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/services/daily_inbox_service.dart';
import 'package:xene_backend/src/services/dragonfly_cache_service.dart';

// Wire up the logging package — must run before any route handler.
// Top-level vars in Dart are lazily initialized, so we reference _loggingReady
// inside _debugMiddleware (which runs on every request) to guarantee it fires first.
// The IIFE returns bool so it can be stored as a final variable.
final bool _loggingReady = () {
  final isDev =
      (Platform.environment['XENE_ENV'] ?? 'development') == 'development';
  Logger.root.level = isDev ? Level.ALL : Level.INFO;
  Logger.root.onRecord.listen((r) {
    final prefix = '[${r.level.name}][${r.loggerName}]';
    print('$prefix ${r.message}');
    if (r.error != null) print('$prefix ERROR: ${r.error}');
    if (r.stackTrace != null) print('$prefix STACK: ${r.stackTrace}');
  });
  return true;
}();

final _logger = Logger('middleware');

// Allowed CORS origins loaded once at startup from ALLOWED_ORIGINS env var.
// Format: comma-separated list, e.g. "https://xene.app,http://localhost:5173"
// If the env var is absent the server falls back to permissive mode (dev-safe).
final _allowedOrigins = () {
  final raw = Platform.environment['ALLOWED_ORIGINS'] ?? '';
  if (raw.trim().isEmpty) return <String>{};
  return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
}();

// True when running with XENE_ENV=production. Used to fail CORS closed when no
// allowlist is configured — production must never echo an arbitrary origin / '*'.
final bool _isProduction =
    (Platform.environment['XENE_ENV'] ?? 'development') == 'production';

// Global singleton instances
final _db = DatabaseService();
final _cache = DragonflyCache();
final _apiAnalytics = ApiAnalyticsService();
final _soundcloud = SoundCloudService(_db, analytics: _apiAnalytics);
final _youtube = YouTubeService(_db, analytics: _apiAnalytics);
final _beatport = BeatportService(_db, analytics: _apiAnalytics);
final _bandcamp = BandcampService(_db, analytics: _apiAnalytics);
final _tokenStore = TokenStore();
final _twitch = TwitchService(analytics: _apiAnalytics);
final _discogs = DiscogsService(analytics: _apiAnalytics);
final _analysis = AnalysisService(_db, analytics: _apiAnalytics);
final _game = GameService(_db);
final _dailyInbox = DailyInboxService(_db);

// Shared Gemini key rotator — one instance for all services so key state is global.
final _geminiRotator = GeminiKeyRotator(analytics: _apiAnalytics);

final _pressScout = PressScoutService(
  _db,
  rotator: _geminiRotator,
  analytics: _apiAnalytics,
);

final _publicationRepo = PublicationRepository(_db.client);
final _publicationPoller = PublicationPollerService(
  _publicationRepo,
  _apiAnalytics.trackDio(
    Dio()
      ..options.connectTimeout = const Duration(seconds: 15)
      ..options.receiveTimeout = const Duration(seconds: 30),
    'publication_rss',
  ),
);

final _discovery = DiscoveryService(
  db: _db,
  soundcloud: _soundcloud,
  discogs: _discogs,
  rotator: _geminiRotator,
  analytics: _apiAnalytics,
);

// Initialize distributed cache at server startup.
final bool _cacheReady = () {
  _cache.init(failOpen: true).then((ok) {
    if (ok) {
      print('[STARTUP] DragonflyDB cache initialized ✓');
    } else {
      print('[STARTUP] DragonflyDB cache disabled (will fall back gracefully)');
    }
  }).catchError((e) {
    print('[STARTUP] DragonflyDB init error (fail-open): $e');
  });
  return true;
}();

// Print env key status at server startup — visible before any request.
final bool _envReady = () {
  print('');
  print('══════════════════════════════════════════════════════');
  print('[XENE SERVER STARTUP] Environment check:');
  print('  Gemini keys loaded: ${_geminiRotator.keyCount}');
  print(
    '  LLM discovery: ${_geminiRotator.hasKeys ? "ENABLED ✓ (${_geminiRotator.keyCount} key(s))" : "DISABLED ✗ — set GEMINI_API_KEY"}',
  );
  print(
    '  PRESS_SCOUT_BATCH_SIZE: ${Platform.environment['PRESS_SCOUT_BATCH_SIZE'] ?? '10 (default)'}',
  );
  print('══════════════════════════════════════════════════════');

  // SECURITY: Warn loudly when production CORS is misconfigured.
  final xeneEnv = Platform.environment['XENE_ENV'] ?? 'development';
  if (xeneEnv == 'production' && _allowedOrigins.isEmpty) {
    print('');
    print('╔══════════════════════════════════════════════════════╗');
    print('║ SECURITY WARNING: ALLOWED_ORIGINS is not set!        ║');
    print('║ Production CORS is now failing CLOSED — all cross-    ║');
    print('║ origin browser requests will be DENIED until you set ║');
    print('║ ALLOWED_ORIGINS=https://your-domain.com              ║');
    print('╚══════════════════════════════════════════════════════╝');
  }

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
  publicationPoller: _publicationPoller,
  publicationRepo: _publicationRepo,
)..start();

final middleware = (Handler handler) {
  return handler
      .use(_jwtMiddleware)
      .use(_corsMiddleware)
      .use(_debugMiddleware)
      .use(provider<DatabaseService>((_) => _db))
      .use(provider<DragonflyCache>((_) => _cache))
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
      .use(provider<GeminiKeyRotator>((_) => _geminiRotator))
      .use(provider<ApiAnalyticsService>((_) => _apiAnalytics))
      .use(provider<PublicationRepository>((_) => _publicationRepo))
      .use(provider<PublicationPollerService>((_) => _publicationPoller))
      .use(provider<AnalysisService>((_) => _analysis))
      .use(provider<GameService>((_) => _game))
      .use(provider<DailyInboxService>((_) => _dailyInbox));
};

Handler _corsMiddleware(Handler handler) {
  return (context) async {
    final requestOrigin = context.request.headers['origin'];

    // Resolve the effective CORS origin to send back.
    // If ALLOWED_ORIGINS is configured, only echo origins on the allowlist.
    // If ALLOWED_ORIGINS is empty (dev / not configured), echo the request origin
    // or fall back to '*' so localhost dev still works without any env setup.
    String effectiveOrigin;
    if (_allowedOrigins.isNotEmpty) {
      // Allowlist configured: echo the origin only if it's on the list,
      // otherwise send a non-matching origin so the browser blocks it.
      effectiveOrigin =
          (requestOrigin != null && _allowedOrigins.contains(requestOrigin))
          ? requestOrigin
          : _allowedOrigins.first;
    } else if (_isProduction) {
      // Fail CLOSED in production when no allowlist is set: never echo an
      // arbitrary origin or '*'. 'null' matches no real origin, so the browser
      // blocks cross-origin requests instead of the server trusting any site.
      effectiveOrigin = 'null';
    } else {
      // Development convenience only — permissive so localhost works with no
      // env setup. Never reached in production (guarded above).
      effectiveOrigin = requestOrigin ?? '*';
    }

    final corsHeaders = {
      'Access-Control-Allow-Origin': effectiveOrigin,
      'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-User-Id, Authorization',
    };

    // 1. Handle Preflight (OPTIONS)
    if (context.request.method == HttpMethod.options) {
      return Response(
        statusCode: HttpStatus.noContent,
        headers: {...corsHeaders, 'Access-Control-Max-Age': '86400'},
      );
    }

    try {
      // 2. Process request then attach CORS headers to response
      final response = await handler(context);
      return response.copyWith(headers: {...response.headers, ...corsHeaders});
    } catch (e, stack) {
      // If the server throws, still send CORS headers so the browser surfaces
      // the real error instead of a misleading "CORS Blocked" message.
      _logger.severe('[middleware] Unhandled exception', e, stack);
      return Response.json(
        statusCode: HttpStatus.internalServerError,
        body: {'error': 'Internal server error'},
        headers: corsHeaders,
      );
    }
  };
}

Handler _debugMiddleware(Handler handler) {
  return (context) async {
    _loggingReady; // triggers lazy init of the logging listener on first request
    _cacheReady; // triggers DragonflyDB init on first request
    _envReady; // triggers env print on first request if startup didn't fire it
    _logger.fine('${context.request.method.value} ${context.request.uri.path}');
    return handler(context);
  };
}

Handler _jwtMiddleware(Handler handler) {
  return (context) async {
    // OPTIONS preflights bypass JWT — CORS handles them in the outer wrapper.
    if (context.request.method == HttpMethod.options) {
      return handler(context);
    }

    final path = context.request.uri.path;
    if (_isJwtExempt(path, context.request.method)) {
      return handler(context);
    }

    final authHeader = context.request.headers['authorization'];
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'error': 'Authorization header required'},
      );
    }

    final token = authHeader.substring(7).trim();
    try {
      final userResp = await _db.client.auth.getUser(token);
      final userId = userResp.user?.id;
      if (userId == null) {
        return Response.json(
          statusCode: HttpStatus.unauthorized,
          body: {'error': 'Invalid or expired token'},
        );
      }
      final isAnon = decodeIsAnonymous(token);
      print('[JWT] auth ok user=$userId isAnonymous=$isAnon path=$path');
      return handler(
        context
            .provide<String>(() => userId)
            .provide<IsAnonymous>(() => IsAnonymous(isAnon)),
      );
    } catch (e) {
      print('[JWT] auth error path=$path: $e');
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'error': 'Authentication failed'},
      );
    }
  };
}

bool _isJwtExempt(String path, HttpMethod method) {
  // OAuth callback paths are browser-navigated — no JWT header possible.
  // /auth/soundcloud/nonce is intentionally NOT exempt: it requires a real JWT.
  if (path == '/auth/soundcloud') return true;
  if (path == '/auth/soundcloud/callback') return true;
  if (path == '/auth/soundcloud/done') return true;
  // Public infrastructure — no user identity needed.
  if (path.startsWith('/proxy/')) return true;
  if (path.startsWith('/twitch/')) return true;
  // /soundcloud/stream requires at least an anonymous session — removed from
  // exempt list so bare API callers without a Xene session are blocked.
  // The Flutter app auto-creates anon JWTs on startup so real users are unaffected.
  if (path == '/discovery/status') return true;
  // /admin/poll is protected by X-Admin-Secret, not JWT.
  if (path == '/admin/poll') return true;
  // Template listing is used by the preset dial for anonymous users.
  // All mutations (POST, PATCH on templates; POST/DELETE on sources) require JWT
  // and are further guarded by requireRealUser() in each handler.
  if (path == '/presets/templates' && method == HttpMethod.get) return true;
  // App UI config is read-only design tokens — no user identity needed.
  if (path == '/config' && method == HttpMethod.get) return true;
  return false;
}
