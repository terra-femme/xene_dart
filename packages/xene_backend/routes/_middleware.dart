import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/database.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/youtube_service.dart';
import 'package:xene_backend/src/services/beatport_service.dart';
import 'package:xene_backend/src/services/bandcamp_service.dart';
import 'package:xene_backend/src/services/scheduler_service.dart';

// Global instances for the lifecycle of the server
final _db = DatabaseService();
final _soundcloud = SoundCloudService(_db);
final _youtube = YouTubeService(_db);
final _beatport = BeatportService(_db);
final _bandcamp = BandcampService(_db);
final _scheduler = SchedulerService(
  db: _db,
  soundcloud: _soundcloud,
  youtube: _youtube,
  beatport: _beatport,
  bandcamp: _bandcamp,
)..start();

// This must be a top-level variable (Handler Function(Handler)) 
// to match the generated Dart Frog server code.
final middleware = (Handler handler) {
  return handler
      .use(_corsMiddleware)
      .use(provider<DatabaseService>((_) => _db))
      .use(provider<SoundCloudService>((_) => _soundcloud))
      .use(provider<YouTubeService>((_) => _youtube))
      .use(provider<BeatportService>((_) => _beatport))
      .use(provider<BandcampService>((_) => _bandcamp))
      .use(provider<SchedulerService>((_) => _scheduler));
};

/// Custom CORS Middleware
Handler _corsMiddleware(Handler handler) {
  return (context) async {
    // 1. Handle preflight (OPTIONS) requests
    if (context.request.method == HttpMethod.options) {
      return Response(
        statusCode: 204,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Requested-With',
        },
      );
    }

    // 2. Process the actual request
    final response = await handler(context);

    // 3. Inject CORS headers into the final response
    return response.copyWith(
      headers: {
        ...response.headers,
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Requested-With',
      },
    );
  };
}