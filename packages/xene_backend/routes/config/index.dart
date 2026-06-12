import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';

final _logger = Logger('config');

/// GET /config
///
/// Returns the active app_ui_config row as design tokens the Flutter app
/// can apply without a binary update. Falls back to hardcoded defaults
/// when the table has no active row.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final db = context.read<DatabaseService>();

  try {
    final rows = await db.client
        .from('app_ui_config')
        .select()
        .eq('is_active', true)
        .limit(1);

    final row = rows.isNotEmpty ? rows.first : null;

    _logger.info(
      '[config] row=${row != null ? "found" : "missing — using defaults"}',
    );

    return Response.json(
      body: {
        'primary_color': row?['primary_color'] as String? ?? '#FF5500',
        'teal_color': row?['teal_color'] as String? ?? '#00C5A5',
        'feed_heading': row?['feed_heading'] as String? ?? 'JUST DROPPED',
        'feed_scroll_speed':
            (row?['feed_scroll_speed'] as num?)?.toDouble() ?? 1.0,
        'nav_labels': row?['nav_labels'],
      },
    );
  } catch (e) {
    _logger.warning('[config] DB error — returning defaults: $e');
    return Response.json(
      body: {
        'primary_color': '#FF5500',
        'teal_color': '#00C5A5',
        'feed_heading': 'JUST DROPPED',
        'feed_scroll_speed': 1.0,
        'nav_labels': null,
      },
    );
  }
}
