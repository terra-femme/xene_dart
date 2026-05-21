import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/database.dart';

final _logger = Logger('discovery.graph');

/// GET /discovery/graph
/// Returns the identity graph for a user's saved artists.
/// Auth: JWT (userId injected via middleware)
/// Returns: {nodes: [...], links: [...]}
///
/// Node types:
///   HUB — the artist itself
///   DATA_POINT — a verified platform profile
///   ANALYSIS — LLM analysis text
///
/// Link types:
///   SUGGESTION — a connection from HUB to a child node
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final userId = context.read<String>();
  _logger.info('[graph] userId=$userId');

  final db = context.read<DatabaseService>();
  final artists = await db.getArtists(userId);

  _logger.info('[graph] Building graph for ${artists.length} artists');

  final nodes = <Map<String, dynamic>>[];
  final links = <Map<String, dynamic>>[];

  for (final artist in artists) {
    final id = artist['id'] as String? ?? '';
    final name = artist['name'] as String? ?? 'Unknown';
    final analysis = artist['analysis'] as String?;
    final entityType = _displayEntityType(
      artist['entity_type'] as String?,
      analysis,
    );
    final confidence = artist['identity_confidence'] as String? ?? 'LOW';
    final coverage = artist['coverage_level'] as String? ?? 'MINIMAL';

    // HUB node for the artist
    final hubId = 'hub-$id';
    nodes.add({
      'id': hubId,
      'label': name,
      'type': 'HUB',
      'data': {
        'entityType': entityType,
        'identityConfidence': confidence,
        'coverageLevel': coverage,
        'soundcloudUsername': artist['soundcloud_username'],
      },
    });

    // DATA_POINT nodes for each known platform link.
    // Column names must exactly match the artists table schema.
    final platforms = <String, String?>{
      'SoundCloud': artist['soundcloud_url'] as String?,
      'YouTube': artist['youtube_url'] as String?,
      'Spotify': artist['spotify_url'] as String?,
      'Beatport': artist['beatport_url'] as String?,
      'Bandcamp': artist['bandcamp_url'] as String?,
      'Instagram': artist['instagram_url'] as String?,
      'Twitch': artist['twitch_url'] as String?,
      'Twitter': artist['twitter_url'] as String?,
    };

    for (final entry in platforms.entries) {
      final url = entry.value;
      if (url == null || url.isEmpty) continue;

      final dpId = 'dp-$id-${entry.key.toLowerCase()}';
      nodes.add({
        'id': dpId,
        'label': entry.key,
        'type': 'DATA_POINT',
        'data': {'url': url},
      });
      links.add({'source': hubId, 'target': dpId, 'type': 'SUGGESTION'});
    }

    // ANALYSIS node if LLM analysis text exists
    if (analysis != null && analysis.isNotEmpty) {
      final analysisId = 'analysis-$id';
      nodes.add({
        'id': analysisId,
        'label': 'LLM Analysis',
        'type': 'ANALYSIS',
        'data': {'text': analysis},
      });
      links.add({'source': hubId, 'target': analysisId, 'type': 'SUGGESTION'});
    }
  }

  _logger.info(
    '[graph] Returning ${nodes.length} nodes, ${links.length} links',
  );

  return Response.json(body: {'nodes': nodes, 'links': links});
}

String _displayEntityType(String? storedType, String? analysis) {
  final normalized = (storedType == null || storedType.trim().isEmpty)
      ? 'artist'
      : storedType.trim().toLowerCase();
  if (normalized != 'artist') return normalized;

  final text = analysis?.toLowerCase() ?? '';
  final labelSignals = [
    'identified as a music label',
    'identified as a label',
    'music label and collective',
    'label and collective',
    'record label',
    'music label',
  ];
  if (labelSignals.any(text.contains)) return 'label';

  final otherSignals = [
    'identified as a venue',
    'identified as an organization',
    'identified as a brand',
  ];
  if (otherSignals.any(text.contains)) return 'other';

  return normalized;
}
