import 'dart:math';
import 'package:logging/logging.dart';
import 'platform_utils.dart';

final _logger = Logger('IdentityEngine');

class IdentityEngine {
  /// Deterministic, entity-type-aware identity confidence scoring.
  /// Ported from identity_engine.py :: calculate_node_confidence
  Map<String, dynamic> calculateNodeConfidence(Map<String, dynamic> data) {
    final entityType = (data['entity_type'] ?? 'artist')
        .toString()
        .toLowerCase();
    final isLabel = entityType == 'label' || entityType == 'organization';

    // Maps each data field to its corresponding *_authority column.
    // Without this, getSignalStrength('soundcloud_username') would look for
    // 'soundcloud_username_authority' which doesn't exist — authority stays 'LOW'.
    const authorityKeyFor = {
      'soundcloud_username': 'soundcloud_authority',
      'youtube_channel_id': 'youtube_authority',
      'spotify_id': 'spotify_authority',
      'beatport_artist_id': 'beatport_authority',
      'bandcamp_url': 'bandcamp_authority',
      'instagram_url': 'instagram_authority',
      'instagram_username': 'instagram_authority',
      'twitter_url': 'twitter_authority',
      'twitter_username': 'twitter_authority',
      'twitch_url': 'twitch_authority',
      'twitch_login': 'twitch_authority',
    };

    double getSignalStrength(String key) {
      final val = data[key];
      if (val == null || val.toString().isEmpty) return 0.0;

      final authorityKey = authorityKeyFor[key] ?? '${key}_authority';
      final authority = data[authorityKey] ?? 'LOW';
      if (authority == 'HIGH') return 1.0;
      if (authority == 'MEDIUM') return 0.8;
      return 0.5; // Default AI scouted
    }

    double identityCores;
    double mediumSignals;
    double weakSignals;
    String entityTag;

    if (isLabel) {
      identityCores =
          getSignalStrength('beatport_artist_id') +
          getSignalStrength('bandcamp_url');
      mediumSignals =
          getSignalStrength('soundcloud_username') +
          getSignalStrength('youtube_channel_id');
      weakSignals =
          getSignalStrength('website_url') +
          getSignalStrength('spotify_id') +
          getSignalStrength('instagram_url') +
          getSignalStrength('twitter_url');
      entityTag = 'label';
    } else {
      identityCores =
          getSignalStrength('spotify_id') +
          getSignalStrength('apple_music_id') +
          getSignalStrength('deezer_id') +
          getSignalStrength('tidal_id');
      mediumSignals =
          getSignalStrength('soundcloud_username') +
          getSignalStrength('youtube_channel_id') +
          getSignalStrength('beatport_artist_id');
      weakSignals =
          getSignalStrength('website_url') +
          getSignalStrength('bandcamp_url') +
          getSignalStrength('instagram_url') +
          getSignalStrength('twitter_url');
      entityTag = 'artist';
    }

    String idConf;
    if (identityCores >= 1.5 ||
        (identityCores >= 0.8 && mediumSignals >= 1.4) ||
        (mediumSignals + weakSignals >= 2.5)) {
      idConf = 'HIGH';
    } else if (identityCores >= 0.8 ||
        (mediumSignals >= 1.4 && weakSignals >= 0.4)) {
      idConf = 'MEDIUM';
    } else {
      idConf = 'LOW';
    }

    final total = identityCores + mediumSignals + weakSignals;
    String coverage;
    if (total >= 4) {
      coverage = 'COMPLETE';
    } else if (total >= 2) {
      coverage = 'PARTIAL';
    } else {
      coverage = 'FRAGMENTED';
    }

    final baseScore =
        (identityCores * 0.40) + (mediumSignals * 0.15) + (weakSignals * 0.05);
    final score = min(baseScore, 1.0);

    _logger.info(
      '[identity_trace] ${data['name'] ?? 'Unknown'} [$entityTag] | cores=$identityCores medium=$mediumSignals weak=$weakSignals → conf=$idConf coverage=$coverage score=${score.toStringAsFixed(2)}',
    );

    return {
      'confidence': double.parse(score.toStringAsFixed(4)),
      'identity_confidence': idConf,
      'coverage_level': coverage,
      'conflict_state': false,
    };
  }

  /// Translate raw AI extraction output into flat artists-table column names.
  /// Ported from identity_engine.py :: map_ai_result_to_artist_fields
  Map<String, dynamic> mapAiResultToArtistFields(
    Map<String, dynamic> aiResult, {
    String artistName = '',
  }) {
    final out = <String, dynamic>{};

    // Capture Canonical Name Override
    final canonicalName =
        aiResult['canonicalName'] ?? aiResult['name'] ?? artistName;
    out['name'] = canonicalName.toString();

    // Improved Label Detection
    final validEntityTypes = {
      'artist',
      'band',
      'label',
      'organization',
      'venue',
      'brand',
      'other',
    };
    final rawEntityType = aiResult['entityType']?.toString().toLowerCase();
    String entityType = rawEntityType ?? 'artist';

    if (entityType == 'artist') {
      final nameLower = canonicalName.toString().toLowerCase();
      if ([
        'recordings',
        'records',
        'productions',
        'music group',
      ].any((w) => nameLower.contains(w))) {
        entityType = 'label';
      }
    }

    if (!validEntityTypes.contains(entityType)) {
      entityType = 'other';
    }

    out['entity_type'] = entityType;

    String? detectPlatformFromId(String rawId) {
      final rawIdLower = rawId.toLowerCase();
      if (rawIdLower.contains('_dnb') ||
          (rawIdLower.contains('_') && !rawId.contains('@'))) {
        if (!rawIdLower.contains('soundcloud')) return 'non_soundcloud';
      }
      if (rawId.startsWith('@') || rawIdLower.contains('/status/'))
        return 'twitter';
      if (!rawId.contains('@') && !rawId.startsWith('http')) {
        if (rawIdLower.contains('soundcloud')) return 'soundcloud';
      }
      return null;
    }

    void setCanonical(String key, String platform, dynamic val) {
      if (val == null ||
          val.toString().toLowerCase() == 'null' ||
          [
            'none',
            'bandcamp',
            'soundcloud',
          ].contains(val.toString().toLowerCase())) {
        return;
      }

      String rawId = val.toString().trim();
      if (rawId.contains('://')) {
        try {
          final uri = Uri.parse(rawId);
          final pathParts = uri.path
              .split('/')
              .where((p) => p.isNotEmpty)
              .toList();
          if (pathParts.isNotEmpty) {
            if (platform == 'soundcloud') {
              rawId = pathParts[0];
            } else if (platform == 'youtube') {
              if (rawId.contains('/channel/')) {
                rawId = pathParts.last;
              } else {
                rawId = pathParts[0];
              }
            } else if (platform == 'beatport') {
              rawId = pathParts.last;
            } else {
              rawId = pathParts.last;
            }
          }
        } catch (_) {}
      }

      if (['youtube', 'twitter'].contains(platform) && rawId.startsWith('@')) {
        rawId = rawId.replaceFirst('@', '');
      }

      final detectedPlatform = detectPlatformFromId(rawId);
      if (platform == 'soundcloud' &&
          detectedPlatform != null &&
          detectedPlatform != 'soundcloud') {
        _logger.warning(
          '[identity_engine] REJECTED: Detected $detectedPlatform data in soundcloud field (raw_id=$rawId)',
        );
        return;
      }

      if (PlatformUtils.validateId(platform, rawId)) {
        out[key] = rawId;
        final fullUrl = PlatformUtils.getCanonicalUrl(
          platform,
          rawId,
          entityType: entityType,
        );
        if (fullUrl != null) {
          out['${platform}_url'] = fullUrl;
        }
      }
    }

    // Platform Mapping
    setCanonical(
      'soundcloud_username',
      'soundcloud',
      _nested(aiResult, ['soundcloudRss', 'url']),
    );
    setCanonical(
      'youtube_channel_id',
      'youtube',
      _nested(aiResult, ['youtube', 'id']),
    );
    setCanonical('spotify_id', 'spotify', _nested(aiResult, ['spotify', 'id']));

    final bcUrl = _nested(aiResult, ['bandcampRss', 'url']);
    if (bcUrl != null) {
      final bcCanonical = PlatformUtils.getCanonicalUrl(
        'bandcamp',
        bcUrl.toString(),
      );
      if (bcCanonical != null) {
        out['bandcamp_url'] = bcCanonical;
      }
    }

    final websiteUrl = _nested(aiResult, ['website', 'url']);
    if (websiteUrl != null) out['website_url'] = websiteUrl.toString();

    if (aiResult['analysis'] != null)
      out['analysis'] = aiResult['analysis'].toString();

    final passive = aiResult['passivePlatforms'] as Map<String, dynamic>? ?? {};

    if (passive['instagram'] != null) {
      final instaUser = passive['instagram'].toString();
      out['instagram_username'] = instaUser;
      final instaUrl = PlatformUtils.getCanonicalUrl('instagram', instaUser);
      if (instaUrl != null) out['instagram_url'] = instaUrl;
    }

    if (passive['twitter'] != null) {
      final twitterUser = passive['twitter'].toString();
      out['twitter_username'] = twitterUser;
      final twitterUrl = PlatformUtils.getCanonicalUrl('twitter', twitterUser);
      if (twitterUrl != null) out['twitter_url'] = twitterUrl;
    }

    // Streaming-only IDs — LLM-found, LOW authority by default.
    // putIfAbsent so SC web-profiles/bio values (written by discovery_service.dart) always win.
    final streaming =
        aiResult['streamingPlatforms'] as Map<String, dynamic>? ?? {};
    final appleId = streaming['appleMusic']?.toString().trim();
    if (appleId != null &&
        appleId.isNotEmpty &&
        appleId.toLowerCase() != 'null') {
      out.putIfAbsent('apple_music_id', () => appleId);
    }
    final deezerId = streaming['deezer']?.toString().trim();
    if (deezerId != null &&
        deezerId.isNotEmpty &&
        deezerId.toLowerCase() != 'null') {
      out.putIfAbsent('deezer_id', () => deezerId);
    }
    final tidalId = streaming['tidal']?.toString().trim();
    if (tidalId != null &&
        tidalId.isNotEmpty &&
        tidalId.toLowerCase() != 'null') {
      out.putIfAbsent('tidal_id', () => tidalId);
    }

    // Twitch — LLM-found, LOW authority. putIfAbsent so SC web-profiles win.
    if (passive['twitch'] != null) {
      final twitchUser = passive['twitch']
          .toString()
          .replaceFirst('@', '')
          .trim();
      if (twitchUser.isNotEmpty && twitchUser.toLowerCase() != 'null') {
        out.putIfAbsent('twitch_login', () => twitchUser);
        out.putIfAbsent(
          'twitch_url',
          () => 'https://www.twitch.tv/$twitchUser',
        );
      }
    }

    final rawEdges = aiResult['suggestedEdges'] as List? ?? [];
    if (rawEdges.isNotEmpty) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      out['edges'] = rawEdges
          .map((e) {
            final edge = e as Map<String, dynamic>;
            return {
              'targetName': edge['targetName'] ?? '',
              'relationship': edge['relationship'] ?? '',
              'sourceUrl': edge['sourceUrl'] ?? '',
              'type': edge['type'] ?? 'AI_SUGGESTED',
              'authorityLevel': 'LOW',
              'lastVerified': nowMs,
            };
          })
          .where((e) => e['targetName'].toString().isNotEmpty)
          .toList();
    }

    return Map<String, dynamic>.fromEntries(
      out.entries.where(
        (e) => e.value != null && e.value.toString().toLowerCase() != 'null',
      ),
    );
  }

  /// Ported from identity_engine.py :: compute_cross_verified
  bool computeCrossVerified(
    Map<String, dynamic> aiResult,
    Map<String, dynamic> scWebProfiles,
  ) {
    if (scWebProfiles.isEmpty) return false;

    final scConfirmedNetworks = scWebProfiles.keys.toSet();
    final aiFoundNetworks = <String>{};

    if (_nested(aiResult, ['spotify', 'id']) != null)
      aiFoundNetworks.add('spotify');
    if (_nested(aiResult, ['youtube', 'id']) != null)
      aiFoundNetworks.add('youtube');
    if (_nested(aiResult, ['bandcampRss', 'url']) != null)
      aiFoundNetworks.add('bandcamp');

    final overlap = scConfirmedNetworks.intersection(aiFoundNetworks);
    if (overlap.isNotEmpty) {
      _logger.info(
        '[identity_engine] cross_verified via SC web-profiles: $overlap',
      );
      return true;
    }
    return false;
  }

  dynamic _nested(Map<String, dynamic> data, List<String> keys) {
    dynamic current = data;
    for (final k in keys) {
      if (current is! Map) return null;
      current = current[k];
    }
    return current;
  }
}
