import 'package:logging/logging.dart';
import 'package:supabase/supabase.dart';

final _logger = Logger('PublicationRepository');

/// Data-access layer for all publication-related tables.
///
/// Sits between the poller/routes and Supabase so callers never write raw
/// Supabase queries. All errors are logged and swallowed at the boundary —
/// a poll failure must not crash the scheduler.
class PublicationRepository {
  PublicationRepository(this._client);

  final SupabaseClient _client;

  /// Returns all enabled publications ordered by tier then name.
  Future<List<Map<String, dynamic>>> getEnabledPublications() async {
    try {
      final response = await _client
          .from('press_publications')
          .select()
          .eq('enabled', true)
          .order('tier')
          .order('name');
      final rows = List<Map<String, dynamic>>.from(response);
      _logger.info(
        '[PublicationRepo] getEnabledPublications: ${rows.length} rows',
      );
      return rows;
    } catch (e) {
      _logger.warning('[PublicationRepo] getEnabledPublications error: $e');
      return [];
    }
  }

  /// Upserts articles into publication_articles.
  /// Conflict on url is ignored — article content doesn't change after publish.
  Future<void> saveArticles(List<Map<String, dynamic>> articles) async {
    if (articles.isEmpty) return;
    try {
      await _client
          .from('publication_articles')
          .upsert(articles, onConflict: 'url');
      _logger.info(
        '[PublicationRepo] Saved/skipped ${articles.length} articles',
      );
    } catch (e) {
      _logger.severe('[PublicationRepo] saveArticles error: $e');
      rethrow;
    }
  }

  /// Stamps a successful poll: resets failure_count, clears last_error,
  /// and updates last_polled to now.
  Future<void> stampPollSuccess(String publicationId) async {
    try {
      await _client
          .from('press_publications')
          .update({
            'last_polled': DateTime.now().toUtc().toIso8601String(),
            'failure_count': 0,
            'last_error': null,
            'last_status': 200,
          })
          .eq('id', publicationId);
    } catch (e) {
      _logger.warning('[PublicationRepo] stampPollSuccess error: $e');
    }
  }

  /// Increments failure_count and records the error via RPC so the update
  /// is atomic (no read-modify-write race between concurrent pollers).
  Future<void> stampPollFailure(
    String publicationId,
    String error, {
    int statusCode = 0,
  }) async {
    try {
      await _client.rpc(
        'increment_publication_failure_count',
        params: {
          'pub_id': publicationId,
          'error_msg': error.length > 500 ? error.substring(0, 500) : error,
          'status': statusCode,
        },
      );
    } catch (e) {
      _logger.warning('[PublicationRepo] stampPollFailure error: $e');
    }
  }

  /// Deletes articles whose expires_at is in the past. Returns the count deleted.
  Future<int> deleteExpiredArticles() async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final response = await _client
          .from('publication_articles')
          .delete()
          .lt('expires_at', now)
          .select('id');
      final count = (response as List).length;
      _logger.info('[PublicationRepo] Deleted $count expired articles');
      return count;
    } catch (e) {
      _logger.warning('[PublicationRepo] deleteExpiredArticles error: $e');
      return 0;
    }
  }

  /// Fetches non-expired articles for a list of publication IDs, newest first.
  /// Joins press_publications so callers get the publication name + slug inline.
  Future<List<Map<String, dynamic>>> getArticlesForPublications(
    List<String> publicationIds, {
    int limit = 20,
  }) async {
    if (publicationIds.isEmpty) return [];
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final response = await _client
          .from('publication_articles')
          .select('*, press_publications(name, slug)')
          .inFilter('publication_id', publicationIds)
          .or('expires_at.is.null,expires_at.gt.$now')
          .order('published_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.warning('[PublicationRepo] getArticlesForPublications error: $e');
      return [];
    }
  }
}
