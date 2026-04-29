import 'dart:math';
import 'package:logging/logging.dart';

final _logger = Logger('IdentityEngine');

class IdentityEngine {
  /// Deterministic, entity-type-aware identity confidence scoring.
  /// Ported from identity_engine.py :: calculate_node_confidence
  Map<String, dynamic> calculateNodeConfidence(Map<String, dynamic> data) {
    final entityType = (data['entity_type'] ?? 'artist').toString().toLowerCase();
    final isLabel = entityType == 'label' || entityType == 'organization';

    double getSignalStrength(String key) {
      final val = data[key];
      if (val == null || val.toString().isEmpty) return 0.0;

      final authority = data['${key}_authority'] ?? 'LOW';
      if (authority == 'HIGH') return 1.0;
      if (authority == 'MEDIUM') return 0.8;
      return 0.5; // Default AI scouted
    }

    double identityCores;
    double mediumSignals;
    double weakSignals;
    String entityTag;

    if (isLabel) {
      identityCores = getSignalStrength('beatport_artist_id') + getSignalStrength('bandcamp_url');
      mediumSignals = getSignalStrength('soundcloud_username') + getSignalStrength('youtube_channel_id');
      weakSignals = getSignalStrength('website_url') + getSignalStrength('spotify_id');
      entityTag = 'label';
    } else {
      identityCores = getSignalStrength('spotify_id') +
          getSignalStrength('apple_music_id') +
          getSignalStrength('deezer_id') +
          getSignalStrength('tidal_id');
      mediumSignals = getSignalStrength('soundcloud_username') +
          getSignalStrength('youtube_channel_id') +
          getSignalStrength('beatport_artist_id');
      weakSignals = getSignalStrength('website_url') + getSignalStrength('bandcamp_url');
      entityTag = 'artist';
    }

    String idConf;
    if (identityCores >= 1.5 || (identityCores >= 0.8 && mediumSignals >= 1.4) || (mediumSignals + weakSignals >= 2.5)) {
      idConf = 'HIGH';
    } else if (identityCores >= 0.8 || (mediumSignals >= 1.4 && weakSignals >= 0.4)) {
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

    final baseScore = (identityCores * 0.40) + (mediumSignals * 0.15) + (weakSignals * 0.05);
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
}
