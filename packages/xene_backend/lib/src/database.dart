import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:logging/logging.dart';

final _logger = Logger('Database');

class DatabaseService {
  SupabaseClient? _client;

  SupabaseClient get client {
    if (_client == null) {
      final url = Platform.environment['SUPABASE_URL'];
      final key = Platform.environment['SUPABASE_SERVICE_KEY'];
      
      if (url == null || key == null) {
        throw StateError('SUPABASE_URL and SUPABASE_SERVICE_KEY must be set.');
      }
      
      _client = SupabaseClient(url, key);
    }
    return _client!;
  }

  Future<List<Map<String, dynamic>>> getCachedFeedItems({
    required String platform,
    String? artistName,
    int limit = 50,
    int days = 31,
  }) async {
    try {
      final cutoff = DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();
      
      var query = client
          .from('feed_items')
          .select()
          .eq('platform', platform)
          .gte('published_at', cutoff);
      
      if (artistName != null) {
        query = query.eq('artist_name', artistName);
      }
      
      final response = await query.order('published_at', ascending: false).limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.severe('Error fetching cached feed items for $platform: $e');
      return [];
    }
  }

  Future<void> saveFeedItems(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    try {
      await client.from('feed_items').upsert(
        items,
        onConflict: 'platform,internal_id',
      );
    } catch (e) {
      _logger.severe('Error saving feed items: $e');
    }
  }

  // --- YouTube Cache Helpers ---

  /// Retrieve cached channel_id from database for a YouTube URL.
  Future<String?> getYouTubeChannelId(String ytUrl) async {
    try {
      final response = await client
          .from('youtube_channel_cache')
          .select('channel_id')
          .eq('yt_url', ytUrl)
          .maybeSingle();
      
      return response?['channel_id'] as String?;
    } catch (e) {
      _logger.fine('Could not query youtube_channel_cache: $e');
      return null;
    }
  }

  /// Store channel_id mapping in database.
  Future<void> saveYouTubeChannelId(String ytUrl, String channelId) async {
    try {
      await client.from('youtube_channel_cache').upsert({
        'yt_url': ytUrl,
        'channel_id': channelId,
      });
    } catch (e) {
      _logger.severe('Error saving channel_id for $ytUrl: $e');
    }
  }

  // --- Artist Helpers ---

  /// Retrieve all artists for a user.
  Future<List<Map<String, dynamic>>> getArtists(String userId) async {
    try {
      final response = await client
          .from('artists')
          .select()
          .eq('user_id', userId)
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.severe('Error fetching artists for $userId: $e');
      return [];
    }
  }

  /// Retrieve a specific artist by ID.
  Future<Map<String, dynamic>?> getArtistById(String id) async {
    try {
      final response = await client
          .from('artists')
          .select()
          .eq('id', id)
          .maybeSingle();
      return response;
    } catch (e) {
      _logger.severe('Error fetching artist $id: $e');
      return null;
    }
  }

  // --- System Cache Helpers ---

  /// Retrieve a value from the system_cache table if not expired.
  /// ELI5: Checking our "Sticky Notes" to see if we already wrote something down.
  Future<Map<String, dynamic>?> getSystemCache(String key) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final response = await client
          .from('system_cache')
          .select('value, expires_at')
          .eq('key', key)
          .maybeSingle();

      if (response != null) {
        final expiresAt = response['expires_at'] as String?;
        if (expiresAt != null) {
          if (expiresAt.compareTo(now) < 0) {
            _logger.fine('System cache expired for key: $key');
            return null;
          }
        }
        return response['value'] as Map<String, dynamic>?;
      }
    } catch (e) {
      _logger.severe('Error reading system_cache for $key: $e');
    }
    return null;
  }

  /// Store a value in the system_cache table.
  /// ELI5: Writing a "Sticky Note" with an expiration date.
  Future<bool> setSystemCache(String key, Map<String, dynamic> value, {DateTime? expiresAt}) async {
    try {
      final data = {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (expiresAt != null) {
        data['expires_at'] = expiresAt.toUtc().toIso8601String();
      }

      await client.from('system_cache').upsert(data);
      return true;
    } catch (e) {
      _logger.severe('Error writing system_cache for $key: $e');
      return false;
    }
  }
}
