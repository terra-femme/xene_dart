import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:googleai_dart/googleai_dart.dart';
import 'package:logging/logging.dart';

import '../database.dart';
import 'gemini_key_rotator.dart';

final _logger = Logger('PressScoutService');

const _kMaxArtistsPerRun = 10;
const _kScoutIntervalDays = 60;
const _kDefaultBatchSize = 10;

class PressScoutService {
  PressScoutService(this.db, {required this.rotator});

  final DatabaseService db;
  final GeminiKeyRotator rotator;

  /// Scheduled background job: scout press for stale artists in batches.
  /// One Gemini grounded call per batch of N artists instead of one per artist.
  Future<void> scoutArticlesForActiveArtists() async {
    _logger.info('[press_scout] Starting active artist press scout');

    if (!rotator.hasKeys) {
      final orKey = Platform.environment['OPENROUTER_API_KEY'];
      if (orKey == null || orKey.isEmpty) {
        _logger.warning('[press_scout] No LLM provider available — scheduled scout skipped');
        return;
      }
      _logger.info('[press_scout] Gemini unavailable — scout will use OpenRouter fallback only');
    }

    // Reset key rotation at the start of each batch run so daily quotas are fresh.
    rotator.reset();

    final allArtists = await db.getAllArtistsForScouting();
    if (allArtists.isEmpty) {
      _logger.info('[press_scout] No artists found in database');
      return;
    }

    final staleAfter = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: _kScoutIntervalDays));

    final toScout = <Map<String, dynamic>>[];
    for (final a in allArtists) {
      if (toScout.length >= _kMaxArtistsPerRun) break;
      final lastStr = a['last_press_scout_at'] as String?;
      if (lastStr == null) {
        toScout.add(a);
      } else {
        try {
          if (DateTime.parse(lastStr).isBefore(staleAfter)) toScout.add(a);
        } catch (_) {
          toScout.add(a);
        }
      }
    }

    if (toScout.isEmpty) {
      _logger.info('[press_scout] No stale artists in queue — skipping');
      return;
    }

    _logger.info('[press_scout] Found ${toScout.length} artists for scouting');

    final batchSize = int.tryParse(
          Platform.environment['PRESS_SCOUT_BATCH_SIZE'] ?? '',
        ) ??
        _kDefaultBatchSize;

    for (var i = 0; i < toScout.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, toScout.length);
      final chunk = toScout.sublist(i, end);
      _logger.info('[press_scout] Processing batch ${i ~/ batchSize + 1}: ${chunk.map((a) => a['name']).toList()}');
      await _scoutBatch(chunk);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  /// Scout a batch of artists in one Gemini grounded call.
  /// Falls back to individual OpenRouter calls per artist if Gemini fails.
  Future<void> _scoutBatch(List<Map<String, dynamic>> artists) async {
    final names = artists.map((a) => a['name'] as String).toList();

    final prompt = _buildBatchPrompt(names);

    Map<String, List<Map<String, dynamic>>>? batchResult;

    if (rotator.hasKeys) {
      batchResult = await _callGeminiBatch(prompt, names);
    }

    if (batchResult != null) {
      // Save results for each artist from the batch response
      for (final artist in artists) {
        final name = artist['name'] as String;
        final artistId = artist['id'] as String;
        final articles = batchResult[name] ?? [];
        await _saveAndUpdate(artistId, name, articles);
      }
    } else {
      // Batch failed — fall back to per-artist OpenRouter calls
      _logger.warning('[press_scout] Batch Gemini failed — falling back to OpenRouter per artist');
      for (final artist in artists) {
        final name = artist['name'] as String;
        final entityType = (artist['entity_type'] as String?) ?? 'artist';
        final artistId = artist['id'] as String;
        final articles = await _scoutWithOpenRouter(name, entityType);
        await _saveAndUpdate(artistId, name, articles);
      }
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>?>  _callGeminiBatch(
    String prompt,
    List<String> names,
  ) async {
    while (true) {
      try {
        final response = await rotator.client.models.generateContent(
          model: 'gemini-2.5-flash',
          request: GenerateContentRequest(
            contents: [Content.text(prompt)],
            tools: [Tool(googleSearch: GoogleSearch())],
          ),
        );
        rotator.logUsage(_logger, 'press_scout.batch(${names.length})', response);

        var text = response.text?.trim() ?? '';
        if (text.contains('```json')) {
          text = text.split('```json')[1].split('```')[0].trim();
        } else if (text.contains('```')) {
          text = text.split('```')[1].split('```')[0].trim();
        }

        if (text.isEmpty) {
          _logger.warning('[press_scout] Gemini batch returned empty text');
          return null;
        }

        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic>) {
          _logger.warning('[press_scout] Gemini batch response is not a JSON object');
          return null;
        }

        final result = <String, List<Map<String, dynamic>>>{};
        for (final name in names) {
          final raw = decoded[name];
          result[name] = raw is List
              ? List<Map<String, dynamic>>.from(raw.whereType<Map>())
              : [];
        }
        _logger.info(
          '[press_scout] Batch result: ${result.map((k, v) => MapEntry(k, v.length))}',
        );
        return result;
      } catch (e) {
        if (GeminiKeyRotator.isQuotaError(e)) {
          _logger.warning('[press_scout] Quota on key ${rotator.currentIndex}: $e');
          if (!rotator.rotate()) return null;
          // Loop continues with next key
        } else {
          _logger.warning('[press_scout] Gemini batch error: $e');
          return null;
        }
      }
    }
  }

  String _buildBatchPrompt(List<String> names) {
    final artistList = names.map((n) => '"$n"').join(', ');
    return '''For each of the following music artists, find the 3 most high-value editorial pieces (interviews, reviews, features) from the last 12 months.

Artists: $artistList

SEARCH STRATEGY:
1. EXHAUSTIVE COVERAGE: Search across the entire spectrum of music media:
   - Tier 1: Global mainstream publications (e.g., NME, Rolling Stone, Billboard).
   - Tier 2: Genre-specific authorities (e.g., DJ Mag for electronic, The Source for Rap, Kerrang for Rock).
   - Tier 3: Independent 'Culture Hubs' and niche blogs (e.g., 1 More Thing, Lyrical Lemonade, local scene zines).

2. FILTERING LOGIC:
   - Prioritize sites with original editorial content over news aggregators.
   - Ignore social media profiles, ticket sales, or auto-generated streaming profiles.
   - Look for keywords like "The Story Of", "In Conversation with", or "Review:".

3. DIVERSITY MANDATE: Include both major outlet and small community blog coverage where available.

Return a JSON object keyed by artist name. Use an empty array for any artist with no results found:
{
  "Artist Name": [{"title": "", "url": "", "snippet": "", "site_tier": "Mainstream/Genre-Specific/Independent"}],
  ...
}''';
  }

  /// Scout articles for a single artist immediately (used on artist add from routes).
  Future<List<Map<String, dynamic>>> scoutOnDemand(
    String artistId,
    String name,
    String entityType,
  ) async {
    if (rotator.hasKeys) {
      final articles = await scoutWithGemini(name, entityType);
      if (articles.isNotEmpty) return articles;
      _logger.warning('[press_scout] Gemini returned empty for $name — trying OpenRouter fallback');
    } else {
      _logger.warning('[press_scout] Gemini client unavailable — trying OpenRouter directly for $name');
    }
    return _scoutWithOpenRouter(name, entityType);
  }

  /// Single-artist Gemini scout with key rotation. Used by scoutOnDemand.
  Future<List<Map<String, dynamic>>> scoutWithGemini(
    String name,
    String entityType,
  ) async {
    final prompt = _buildSinglePrompt(name);

    while (true) {
      try {
        final response = await rotator.client.models.generateContent(
          model: 'gemini-2.5-flash',
          request: GenerateContentRequest(
            contents: [Content.text(prompt)],
            tools: [Tool(googleSearch: GoogleSearch())],
          ),
        );
        rotator.logUsage(_logger, 'press_scout.single', response);

        var text = response.text?.trim() ?? '';
        if (text.contains('```json')) {
          text = text.split('```json')[1].split('```')[0].trim();
        } else if (text.contains('```')) {
          text = text.split('```')[1].split('```')[0].trim();
        }

        if (text.isEmpty) {
          _logger.warning('[press_scout] Gemini returned empty response for $name');
          return [];
        }

        final decoded = jsonDecode(text);
        final articles = decoded is List
            ? List<Map<String, dynamic>>.from(decoded)
            : decoded is Map && decoded.containsKey('articles')
                ? List<Map<String, dynamic>>.from(decoded['articles'] as List)
                : <Map<String, dynamic>>[];

        _logger.info('[press_scout] Gemini returned ${articles.length} articles for $name');
        return articles;
      } catch (e) {
        if (GeminiKeyRotator.isQuotaError(e)) {
          _logger.warning('[press_scout] Quota on key ${rotator.currentIndex}: $e');
          if (!rotator.rotate()) return [];
        } else {
          print('[XENE PRESS_SCOUT] ✗ Gemini scout THREW for "$name": $e');
          _logger.warning('[press_scout] Gemini scout failed for $name: $e');
          return [];
        }
      }
    }
  }

  String _buildSinglePrompt(String name) {
    return '''Identify the musical genre of "$name" and perform a comprehensive search for recent press.

GOAL: Find the 5 most high-value editorial pieces (interviews, reviews, features) from the last 12 months.

SEARCH STRATEGY:
1. EXHAUSTIVE COVERAGE: Use Google Search to look across the entire spectrum of music media:
   - Tier 1: Global mainstream publications (e.g., NME, Rolling Stone, Billboard).
   - Tier 2: Genre-specific authorities (e.g., DJ Mag for electronic, The Source for Rap, Kerrang for Rock).
   - Tier 3: Independent 'Culture Hubs' and niche blogs (e.g., 1 More Thing, Lyrical Lemonade, local scene zines).

2. FILTERING LOGIC:
   - Prioritize sites with original editorial content over news aggregators.
   - Ignore social media profiles, ticket sales, or auto-generated streaming profiles.
   - Look for keywords like "The Story Of", "In Conversation with", or "Review:".

3. DIVERSITY MANDATE: If "$name" has coverage in both a major outlet and a small community blog, include both to show the breadth of their reach.

Return as a JSON list: [{"title": "", "url": "", "snippet": "", "site_tier": "Mainstream/Genre-Specific/Independent"}]''';
  }

  Future<void> _saveAndUpdate(
    String artistId,
    String name,
    List<Map<String, dynamic>> articles,
  ) async {
    if (articles.isNotEmpty) {
      final dbArticles = _mapArticlesToDb(artistId, articles);
      if (await db.saveArtistArticles(dbArticles)) {
        await db.updateLastPressScout(artistId);
        _logger.info('[press_scout] Saved ${dbArticles.length} articles for $name');
      } else {
        _logger.warning('[press_scout] Failed to save articles for $name — will retry next cycle');
      }
    } else {
      _logger.info('[press_scout] No articles found for $name');
    }
  }

  Future<List<Map<String, dynamic>>> _scoutWithOpenRouter(
    String name,
    String entityType,
  ) async {
    final apiKey = Platform.environment['OPENROUTER_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      print('[XENE OPENROUTER] *** PRESS SCOUT FALLBACK SKIPPED — OPENROUTER_API_KEY not set ***');
      _logger.warning('[press_scout._scoutWithOpenRouter] OPENROUTER_API_KEY not set — fallback disabled');
      return [];
    }

    print('');
    print('[XENE OPENROUTER] ▶▶▶ Press scout OpenRouter fallback for "$name"');
    _logger.info('[press_scout._scoutWithOpenRouter] ▶ calling OpenRouter for "$name" [$entityType]');

    final prompt = _buildSinglePrompt(name);

    try {
      final dio = Dio();
      final response = await dio.post<Map<String, dynamic>>(
        'https://openrouter.ai/api/v1/chat/completions',
        data: {
          'model': 'openrouter/free',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 1024,
          'provider': {
            'allow_fallbacks': true,
            'order': ['Google', 'Anthropic', 'OpenAI'],
          },
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'X-Title': 'Xene Press Scout',
          },
        ),
      );

      print('[XENE OPENROUTER] ◀◀◀ Press scout response — status=${response.statusCode}');
      _logger.info('[press_scout._scoutWithOpenRouter] ← status=${response.statusCode}');

      final content = (response.data?['choices'] as List?)
              ?.firstOrNull?['message']?['content']
              ?.toString() ??
          '';
      _logger.info('[press_scout._scoutWithOpenRouter] content length=${content.length}');

      if (content.isEmpty) {
        _logger.warning('[press_scout._scoutWithOpenRouter] ⚠ empty content — returning []');
        return [];
      }

      var text = content.trim();
      if (text.contains('```json')) {
        text = text.split('```json')[1].split('```')[0].trim();
      } else if (text.contains('```')) {
        text = text.split('```')[1].split('```')[0].trim();
      }

      final decoded = jsonDecode(text);
      final articles = decoded is List
          ? List<Map<String, dynamic>>.from(decoded)
          : decoded is Map && decoded.containsKey('articles')
              ? List<Map<String, dynamic>>.from(decoded['articles'] as List)
              : <Map<String, dynamic>>[];

      print('[XENE OPENROUTER] ✓ Press scout returned ${articles.length} articles for "$name"');
      _logger.info('[press_scout._scoutWithOpenRouter] ✓ ${articles.length} articles for $name');
      return articles;
    } catch (e, st) {
      print('[XENE OPENROUTER] ✗ Press scout OpenRouter THREW for "$name": $e');
      _logger.warning('[press_scout._scoutWithOpenRouter] ✗ failed for $name: $e');
      _logger.warning('[press_scout._scoutWithOpenRouter] stacktrace: $st');
      return [];
    }
  }

  List<Map<String, dynamic>> _mapArticlesToDb(
    String artistId,
    List<Map<String, dynamic>> articles,
  ) {
    return articles.map((art) {
      final rawDate = art['published_date'] ?? art['Date'];
      final pubDate = rawDate?.toString().trim().toLowerCase();
      final pubDateVal =
          (pubDate != null && pubDate != 'n/a' && pubDate != 'unknown' && pubDate.isNotEmpty)
              ? rawDate.toString()
              : null;
      return {
        'artist_id': artistId,
        'title': art['title'] ?? art['Title'] ?? 'Untitled',
        'url': art['url'] ?? art['URL'] ?? '#',
        'snippet': art['snippet'] ?? art['Snippet'] ?? 'No snippet available',
        'source': art['source'] ?? art['Source'] ?? art['site_tier'] ?? art['Site_tier'],
        'published_at': pubDateVal,
      };
    }).toList();
  }
}
