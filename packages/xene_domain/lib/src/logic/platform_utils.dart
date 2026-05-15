/// Platform utilities for ID validation and canonical URL synthesis.
/// Ported from platform_utils.py
class PlatformUtils {
  // Regex for YouTube channel IDs (must start with UC and be 24 chars)
  static final _ytChannelRe = RegExp(r'^UC[a-zA-Z0-9_-]{22}$');
  // Regex for numeric IDs (Beatport)
  static final _numericIdRe = RegExp(r'^\d+$');

  /// Check if a platform identifier matches its expected format.
  /// Also catches common AI hallucinations.
  static bool validateId(String platform, String identifier) {
    if (identifier.isEmpty) return false;

    final val = identifier.trim();
    final vLow = val.toLowerCase();

    // Block common hallucinations
    if (['null', 'bandcamp', 'soundcloud', 'spotify', 'youtube', 'beatport'].contains(vLow)) {
      return false;
    }

    if (platform == 'youtube') {
      return _ytChannelRe.hasMatch(val) || 
             val.startsWith('@') || 
             (val.length < 20 && val.length > 2);
    }
    
    if (['beatport', 'beatport_artist', 'beatport_label'].contains(platform)) {
      return _numericIdRe.hasMatch(val);
    }
    
    if (platform == 'spotify') {
      // Spotify IDs must be exactly 22 alphanumeric chars
      return val.length == 22 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(val);
    }

    return true;
  }

  /// Synthesize a full, clickable URL from a raw platform identifier.
  static String? getCanonicalUrl(String platform, String identifier, {String entityType = 'artist', String? slug}) {
    if (identifier.isEmpty || identifier.toLowerCase() == 'null') {
      return null;
    }

    final val = identifier.trim();
    if (val.isEmpty) return null;

    if (val.startsWith('http')) {
      return val.replaceAll(RegExp(r'/$'), '');
    }

    if (platform == 'youtube') {
      if (_ytChannelRe.hasMatch(val)) {
        return 'https://www.youtube.com/channel/$val';
      }
      if (val.startsWith('@')) {
        return 'https://www.youtube.com/$val';
      }
      if (val.length < 30 && !val.startsWith('UC')) {
        return 'https://www.youtube.com/@$val';
      }
      return null;
    }

    if (platform == 'spotify') {
      if (val.length == 22 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(val)) {
        return 'https://open.spotify.com/artist/$val';
      }
      return null;
    }

    if (platform == 'beatport') {
      if (!_numericIdRe.hasMatch(val)) {
        return null;
      }
      final path = (entityType == 'label' || entityType == 'organization') ? 'label' : 'artist';
      // Robust slug fallback
      final cleanSlug = slug ?? 'feed';
      return 'https://www.beatport.com/$path/$cleanSlug/$val';
    }

    if (platform == 'soundcloud') {
      if (val.length < 2 || val.toLowerCase() == 'soundcloud') {
        return null;
      }
      return 'https://soundcloud.com/$val';
    }

    if (platform == 'bandcamp') {
      if (val.isNotEmpty && !val.contains('.') && val.length > 2) {
        return 'https://$val.bandcamp.com';
      }
      return null;
    }

    if (platform == 'instagram') {
      return 'https://instagram.com/${val.replaceFirst('@', '')}';
    }

    if (['twitter', 'x'].contains(platform)) {
      return 'https://x.com/${val.replaceFirst('@', '')}';
    }

    return null;
  }
}
