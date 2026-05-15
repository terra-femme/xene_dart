import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:googleai_dart/googleai_dart.dart';
import 'package:logging/logging.dart';
import 'package:xene_domain/xene_domain.dart';

import '../database.dart';
import 'gemini_key_rotator.dart';
import 'soundcloud_service.dart';
import 'discogs_service.dart';

final _logger = Logger('DiscoveryService');

String _redactSensitiveText(Object value) {
  return value
      .toString()
      .replaceAll(RegExp(r'key=[^&\s]+'), 'key=***REDACTED***')
      .replaceAll(
        RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+'),
        'Bearer ***REDACTED***',
      );
}

String _contentToString(dynamic content) {
  if (content == null) return '';
  if (content is String) return content;
  if (content is List) {
    return content
        .map((part) {
          if (part is String) return part;
          if (part is Map) return part['text']?.toString() ?? '';
          return '';
        })
        .where((part) => part.isNotEmpty)
        .join('\n');
  }
  return content.toString();
}

String _summarizeOpenRouterResponse(Map<String, dynamic>? data) {
  if (data == null) return 'null body';
  final choices = data['choices'];
  final firstChoice = choices is List && choices.isNotEmpty
      ? choices.first
      : null;
  final message = firstChoice is Map ? firstChoice['message'] : null;
  final messageMap = message is Map ? message : const {};
  return {
    'keys': data.keys.toList(),
    'choicesLength': choices is List ? choices.length : null,
    'finishReason': firstChoice is Map ? firstChoice['finish_reason'] : null,
    'nativeFinishReason': firstChoice is Map
        ? firstChoice['native_finish_reason']
        : null,
    'messageKeys': messageMap.keys.toList(),
    'hasReasoning': messageMap['reasoning']?.toString().isNotEmpty ?? false,
    'hasRefusal': messageMap['refusal']?.toString().isNotEmpty ?? false,
    'error': data['error'],
  }.toString();
}

// Platforms that have a corresponding _authority column in the artists table.
const _kAuthorityPlatforms = {
  'soundcloud',
  'youtube',
  'spotify',
  'beatport',
  'bandcamp',
  'instagram',
  'twitter',
  'twitch',
};

class DiscoveryService {
  DiscoveryService({
    required this.db,
    required this.soundcloud,
    required this.discogs,
    required this.rotator,
  });

  final DatabaseService db;
  final SoundCloudService soundcloud;
  final DiscogsService discogs;
  final GeminiKeyRotator rotator;

  bool get hasProviders => rotator.hasKeys;

  bool _isAmbiguousName(String name) {
    final s = name.trim().toLowerCase();
    if (s.isEmpty) return false;
    final ambiguous = {
      'justice',
      'lsd',
      'soma',
      'echo',
      'oasis',
      'jungle',
      'lorde',
      'air',
    };
    return ambiguous.contains(s);
  }

  /// Apply Discogs fetchEntityLinks result to mappedFields (HIGH authority).
  void _applyDiscogsData(
    Map<String, dynamic> dData,
    Map<String, dynamic> mappedFields,
  ) {
    if (dData.isEmpty) return;
    final dLinks = dData['links'] as Map<String, dynamic>? ?? {};
    _logger.info('[discovery] Applying Discogs links: ${dLinks.keys.toList()}');
    for (final mapping in {
      'bandcamp': 'bandcamp_url',
      'beatport': 'beatport_url',
      'spotify': 'spotify_url',
      'youtube': 'youtube_url',
      'twitter': 'twitter_url',
      'website': 'website_url',
    }.entries) {
      final val = dLinks[mapping.key] as String?;
      if (val != null) {
        mappedFields[mapping.value] = val;
        if (_kAuthorityPlatforms.contains(mapping.key)) {
          mappedFields['${mapping.key}_authority'] = 'HIGH';
        }
        _logger.info('[discovery] Discogs→${mapping.key}: $val');
      }
    }
  }

  /// Run a single-pass LLM identity walk for an artist.
  Future<Map<String, dynamic>> autoDiscover(
    String name, {
    String? scBio,
    String? scProfileUrl,
    String? scUsername,
    bool skipLlm = false,
  }) async {
    print('');
    print('══════════════════════════════════════════════════');
    print('[XENE DISCOVERY] autoDiscover() STARTED');
    print('[XENE DISCOVERY] name="$name"');
    print('[XENE DISCOVERY] scProfileUrl=$scProfileUrl');
    print('[XENE DISCOVERY] scUsername=$scUsername');
    print('[XENE DISCOVERY] scBio length=${scBio?.length ?? 0}');
    _logger.info(
      '[discovery.autoDiscover] ▶ CALLED name="$name" scUsername="$scUsername" scProfileUrl="$scProfileUrl"',
    );

    final hasLlm = rotator.hasKeys;
    final isAmbiguous = _isAmbiguousName(name);
    print('[XENE DISCOVERY] LLM client available: ${rotator.hasKeys}');
    print('[XENE DISCOVERY] isAmbiguousName: $isAmbiguous');
    print('══════════════════════════════════════════════════');
    _logger.info(
      '[discovery.autoDiscover] hasLlm=$hasLlm keys=${rotator.keyCount} isAmbiguous=$isAmbiguous',
    );

    // ── LAYER 1: Gather raw signals ──────────────────────────────────────────

    // 1a. SC web-profiles (artist-verified = ground truth)
    Map<String, dynamic> scWebProfiles = {};
    if (scProfileUrl != null) {
      _logger.info(
        '[discovery.autoDiscover] → fetching SC web-profiles for $scProfileUrl',
      );
      try {
        scWebProfiles = await soundcloud.fetchWebProfiles(scProfileUrl);
        _logger.info(
          '[discovery.autoDiscover] SC web-profiles count=${scWebProfiles.length} keys=${scWebProfiles.keys.toList()}',
        );
      } catch (e) {
        _logger.warning(
          '[discovery.autoDiscover] ⚠ SC web-profiles fetch failed: $e',
        );
      }
    } else {
      _logger.info(
        '[discovery.autoDiscover] no scProfileUrl — skipping web-profiles fetch',
      );
    }

    // 1b. SC bio regex extraction (HIGH authority — explicit artist-typed links)
    final bioLinks = soundcloud.extractLinksFromBio(scBio);
    _logger.info(
      '[discovery.autoDiscover] bio links found: ${bioLinks.keys.toList()}',
    );

    // ── Early Discogs check from SC sources (before LLM) ────────────────────
    print('[DEBUG discogs] scWebProfiles keys: ${scWebProfiles.keys.toList()}');
    print(
      '[DEBUG discogs] scWebProfiles[discogs]: ${scWebProfiles['discogs']}',
    );

    String? discogsUrl = scWebProfiles['discogs']?['url'] as String?;
    discogsUrl ??= bioLinks['discogs'];

    print('[DEBUG discogs] discogsUrl resolved: $discogsUrl');

    Map<String, dynamic> earlyDiscogsData = {};
    if (discogsUrl != null) {
      _logger.info(
        '[discovery.autoDiscover] Discogs found early (bio/web-profiles): $discogsUrl — running multi-hop',
      );
      try {
        earlyDiscogsData = await discogs.fetchEntityLinks(discogsUrl);
        _logger.info(
          '[discovery.autoDiscover] Early Discogs: ${earlyDiscogsData.length} fields, links=${(earlyDiscogsData['links'] as Map?)?.keys.toList()}',
        );
        print(
          '[DEBUG discogs] earlyDiscogsData keys: ${earlyDiscogsData.keys.toList()}',
        );
        print(
          '[DEBUG discogs] earlyDiscogsData[links]: ${earlyDiscogsData['links']}',
        );
      } catch (e) {
        _logger.warning(
          '[discovery.autoDiscover] ⚠ Early Discogs fetch failed: $e',
        );
      }
    } else {
      print(
        '[DEBUG discogs] No Discogs URL found from SC web-profiles or bio — skipping early multi-hop',
      );
    }

    // ── LAYER 2: Build rich seed context for LLM ────────────────────────────
    final contextParts = <String>[];
    contextParts.add('Artist display name: "$name"');
    if (scUsername != null) {
      contextParts.add('SoundCloud permalink (username slug): "$scUsername"');
      contextParts.add(
        'Note: the display name and permalink may differ — search for BOTH when finding links on other platforms.',
      );
    }
    if (scProfileUrl != null)
      contextParts.add('SoundCloud profile: $scProfileUrl');
    if (scBio != null && scBio.isNotEmpty)
      contextParts.add('SoundCloud bio: $scBio');

    if (scWebProfiles.isNotEmpty) {
      contextParts.add(
        'Verified Platform Links (set by artist on SoundCloud):',
      );
      scWebProfiles.forEach((net, val) {
        final url = val['url'] as String?;
        final id = val['id'] as String?;
        if (url != null) {
          final handleNote = (id != null && id.isNotEmpty)
              ? ' (handle: $id)'
              : '';
          contextParts.add('- $net: $url$handleNote');
        }
      });
    }

    if (earlyDiscogsData.isNotEmpty) {
      final dLinks = earlyDiscogsData['links'] as Map<String, dynamic>? ?? {};
      if (dLinks.isNotEmpty) {
        contextParts.add('Discogs profile links (curated catalog data):');
        dLinks.forEach((k, v) => contextParts.add('- $k: $v'));
      }
      if (earlyDiscogsData['name'] != null) {
        contextParts.add(
          'Discogs canonical name: "${earlyDiscogsData['name']}"',
        );
      }
    }

    final seedContext = contextParts.join('\n');
    _logger.info(
      '[discovery.autoDiscover] seedContext lines=${contextParts.length}',
    );
    _logger.info(
      '[discovery.autoDiscover] seedContext preview: "${seedContext.substring(0, seedContext.length.clamp(0, 300))}"',
    );

    // ── LAYER 2.5: Pre-LLM Mapping (Rate-Limit Proofing) ───────────────────
    final preLlmMappedFields = <String, dynamic>{};

    // Assign SC identity fields early
    if (scUsername != null)
      preLlmMappedFields['soundcloud_username'] = scUsername;
    if (scProfileUrl != null)
      preLlmMappedFields['soundcloud_url'] = scProfileUrl;
    preLlmMappedFields['soundcloud_authority'] = 'HIGH';

    // Map official web-profiles (highest priority)
    for (final entry in scWebProfiles.entries) {
      final net = entry.key;
      final val = entry.value as Map<String, dynamic>;
      final url = val['url'] as String?;
      final id = val['id'] as String?;
      if (url == null) continue;

      if (_kAuthorityPlatforms.contains(net)) {
        preLlmMappedFields['${net}_authority'] = 'HIGH';
      }

      switch (net) {
        case 'youtube':
          preLlmMappedFields['youtube_url'] = url;
          if (id != null && id.startsWith('UC'))
            preLlmMappedFields['youtube_channel_id'] = id;
        case 'twitter':
          preLlmMappedFields['twitter_url'] = url;
          if (id != null) preLlmMappedFields['twitter_username'] = id;
        case 'spotify':
          preLlmMappedFields['spotify_url'] = url;
          if (id != null) preLlmMappedFields['spotify_id'] = id;
        case 'bandcamp':
          preLlmMappedFields['bandcamp_url'] = url;
        case 'instagram':
          preLlmMappedFields['instagram_url'] = url;
          if (id != null) preLlmMappedFields['instagram_username'] = id;
        case 'twitch':
          preLlmMappedFields['twitch_url'] = url;
          if (id != null) preLlmMappedFields['twitch_login'] = id;
        case 'beatport':
          preLlmMappedFields['beatport_url'] = url;
      }
    }

    // ── LLM call ─────────────────────────────────────────────────────────────
    Map<String, dynamic> aiResult = {};
    if (skipLlm) {
      print(
        '[XENE DISCOVERY] skipLlm=true — skipping LLM, using SC+Discogs data only',
      );
      _logger.info('[discovery.autoDiscover] skipLlm=true — bypassing LLM');
    } else if (hasLlm) {
      print('');
      print('[XENE DISCOVERY] ▶▶▶ CALLING GEMINI LLM for "$name"');
      _logger.info('[discovery.autoDiscover] → calling LLM identity walk');
      aiResult = await _runLlmIdentityWalk(name, seedContext);
      print(
        '[XENE DISCOVERY] ◀◀◀ GEMINI RETURNED ${aiResult.length} fields: ${aiResult.keys.toList()}',
      );
      _logger.info(
        '[discovery.autoDiscover] ← LLM returned ${aiResult.length} fields: ${aiResult.keys.toList()}',
      );

      if (aiResult.isEmpty) {
        print(
          '[XENE DISCOVERY] ⚠ Gemini returned empty — trying OpenRouter fallback',
        );
        _logger.warning(
          '[discovery.autoDiscover] ⚠ Gemini returned empty — falling back to OpenRouter',
        );
        aiResult = await _runOpenRouterFallback(name, seedContext);
        if (aiResult.isEmpty) {
          print(
            '[XENE DISCOVERY] OpenRouter returned empty - trying NVIDIA fallback',
          );
          _logger.warning(
            '[discovery.autoDiscover] OpenRouter returned empty - falling back to NVIDIA',
          );
          aiResult = await _runNvidiaFallback(name, seedContext);
          _logger.info(
            '[discovery.autoDiscover] NVIDIA fallback returned ${aiResult.length} fields',
          );
        }
        _logger.info(
          '[discovery.autoDiscover] ← OpenRouter fallback returned ${aiResult.length} fields',
        );
      }
    } else {
      print(
        '[XENE DISCOVERY] *** GEMINI UNAVAILABLE *** — trying OpenRouter directly.',
      );
      _logger.warning(
        '[discovery.autoDiscover] ⚠ No Gemini keys configured — attempting OpenRouter fallback',
      );
      aiResult = await _runOpenRouterFallback(name, seedContext);
      if (aiResult.isEmpty) {
        print(
          '[XENE DISCOVERY] OpenRouter unavailable/empty - trying NVIDIA fallback',
        );
        _logger.warning(
          '[discovery.autoDiscover] OpenRouter unavailable/empty - falling back to NVIDIA',
        );
        aiResult = await _runNvidiaFallback(name, seedContext);
        _logger.info(
          '[discovery.autoDiscover] NVIDIA fallback returned ${aiResult.length} fields',
        );
      }
      _logger.info(
        '[discovery.autoDiscover] ← OpenRouter returned ${aiResult.length} fields',
      );
    }

    // Extract entityType early (needed for proactive Discogs search)
    final entityType = (aiResult['entityType'] as String? ?? 'artist')
        .toLowerCase();
    _logger.info(
      '[discovery.autoDiscover] entityType="$entityType" (from LLM)',
    );

    // Propagate Discogs canonical name into aiResult before engine runs
    if (earlyDiscogsData['name'] != null) {
      aiResult.putIfAbsent('canonicalName', () => earlyDiscogsData['name']);
    }

    // ── LAYER 3: Deterministic verification (post-LLM) ───────────────────────

    // Check if LLM found a Discogs URL we haven't seen yet
    String? llmDiscogsUrl;
    final websiteUrl = aiResult['website']?['url']?.toString();
    if (websiteUrl != null && websiteUrl.contains('discogs.com')) {
      llmDiscogsUrl = websiteUrl;
    } else {
      final suggestedEdges = aiResult['suggestedEdges'] as List? ?? [];
      for (final edge in suggestedEdges) {
        final src = edge['sourceUrl']?.toString() ?? '';
        if (src.contains('discogs.com')) {
          llmDiscogsUrl = src;
          break;
        }
      }
    }
    _logger.info(
      '[discovery.autoDiscover] llmDiscogsUrl=${llmDiscogsUrl ?? "none"}',
    );

    Map<String, dynamic> lateDiscogsData = {};
    if (llmDiscogsUrl != null && llmDiscogsUrl != discogsUrl) {
      _logger.info(
        '[discovery.autoDiscover] LLM found new Discogs URL: $llmDiscogsUrl — running multi-hop',
      );
      try {
        lateDiscogsData = await discogs.fetchEntityLinks(llmDiscogsUrl);
        discogsUrl = llmDiscogsUrl;
        if (lateDiscogsData['name'] != null) {
          aiResult.putIfAbsent('canonicalName', () => lateDiscogsData['name']);
        }
        _logger.info(
          '[discovery.autoDiscover] Late Discogs: ${lateDiscogsData.length} fields',
        );
      } catch (e) {
        _logger.warning(
          '[discovery.autoDiscover] ⚠ Late Discogs multi-hop failed: $e',
        );
      }
    }

    // Proactive Discogs search if no Discogs URL found from any source.
    // Skipped in skipLlm mode — entityType defaults to 'artist' without LLM
    // and the extra HTTP call would add latency to the fast path.
    Map<String, dynamic> proactiveDiscogsData = {};
    if (discogsUrl == null && !skipLlm) {
      _logger.info(
        '[discovery.autoDiscover] No Discogs URL from any source — trying proactive search for "$name" as $entityType',
      );
      try {
        proactiveDiscogsData = await discogs.searchEntity(
          name,
          entityType: entityType,
        );
        if (proactiveDiscogsData.isNotEmpty) {
          _logger.info(
            '[discovery.autoDiscover] Proactive Discogs match: name=${proactiveDiscogsData['name']}',
          );
          if (proactiveDiscogsData['name'] != null) {
            aiResult.putIfAbsent(
              'canonicalName',
              () => proactiveDiscogsData['name'],
            );
          }
        } else {
          _logger.info(
            '[discovery.autoDiscover] Proactive Discogs: no match above threshold',
          );
        }
      } catch (e) {
        _logger.warning(
          '[discovery.autoDiscover] ⚠ Proactive Discogs search failed: $e',
        );
      }
    }

    // ── LAYER 4: Identity Engine + field mapping ─────────────────────────────
    _logger.info(
      '[discovery.autoDiscover] → mapping aiResult to flat fields. aiResult keys: ${aiResult.keys.toList()}',
    );
    final engine = IdentityEngine();

    // Initialize mappedFields with our Rate-Limit Proof data
    final mappedFields = Map<String, dynamic>.from(preLlmMappedFields);

    // Enrich with LLM results
    final engineResults = engine.mapAiResultToArtistFields(
      aiResult,
      artistName: name,
    );
    engineResults.forEach((key, value) {
      // Don't overwrite HIGH authority data from SoundCloud API with LLM guesses
      if (mappedFields['${key.split('_').first}_authority'] != 'HIGH') {
        mappedFields[key] = value;
      }
    });

    _logger.info(
      '[discovery.autoDiscover] mappedFields after engine: ${mappedFields.keys.toList()}',
    );

    // Apply Discogs data (all sources) — HIGH authority, overwrites LLM guesses
    _applyDiscogsData(earlyDiscogsData, mappedFields);
    _applyDiscogsData(lateDiscogsData, mappedFields);
    _applyDiscogsData(proactiveDiscogsData, mappedFields);

    // SC bio links — putIfAbsent (fills gaps LLM + Discogs missed)
    for (final entry in bioLinks.entries) {
      final net = entry.key;
      final url = entry.value;
      switch (net) {
        case 'youtube':
          mappedFields.putIfAbsent('youtube_url', () => url);
        case 'twitter':
          mappedFields.putIfAbsent('twitter_url', () => url);
        case 'spotify':
          mappedFields.putIfAbsent('spotify_url', () => url);
        case 'bandcamp':
          mappedFields.putIfAbsent('bandcamp_url', () => url);
        case 'beatport':
          mappedFields.putIfAbsent('beatport_url', () => url);
        case 'instagram':
          mappedFields.putIfAbsent('instagram_url', () => url);
        default:
          break;
      }
      if (_kAuthorityPlatforms.contains(net)) {
        mappedFields.putIfAbsent('${net}_authority', () => 'HIGH');
      }
      _logger.info('[discovery.autoDiscover] bio link applied: $net → $url');
    }

    // SC web-profiles — Store unrecognized links in edges (tiktok, patreon, etc.)
    for (final entry in scWebProfiles.entries) {
      final net = entry.key;
      final val = entry.value as Map<String, dynamic>;
      final url = val['url'] as String?;

      if (url != null &&
          !_kAuthorityPlatforms.contains(net) &&
          net != 'discogs') {
        final existingEdges = (mappedFields['edges'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        mappedFields['edges'] = [
          ...existingEdges,
          {
            'targetName': net,
            'relationship': 'SC_WEB_PROFILE',
            'sourceUrl': url,
            'type': 'SC_WEB_PROFILE',
            'authorityLevel': 'HIGH',
            'lastVerified': DateTime.now().millisecondsSinceEpoch,
          },
        ];
        _logger.info(
          '[discovery.autoDiscover] extra SC link stored in edges: $net → $url',
        );
      }
    }

    final crossVerified = engine.computeCrossVerified(aiResult, scWebProfiles);
    _logger.info('[discovery.autoDiscover] crossVerified=$crossVerified');

    // SC identity is always HIGH
    if (scUsername != null || scProfileUrl != null) {
      mappedFields['soundcloud_authority'] = 'HIGH';
      _logger.info('[discovery.autoDiscover] set soundcloud_authority=HIGH');
    }

    // Default everything else to LOW
    for (final p in _kAuthorityPlatforms) {
      mappedFields.putIfAbsent('${p}_authority', () => 'LOW');
    }
    if (crossVerified) {
      mappedFields['identity_confidence_source'] = 'CROSS_VERIFIED';
    }

    final scoring = engine.calculateNodeConfidence(mappedFields);
    mappedFields.addAll(scoring);

    // Stamp discovery timestamp
    mappedFields['last_discovered_at'] = DateTime.now()
        .toUtc()
        .toIso8601String();
    _logger.info('[discovery.autoDiscover] last_discovered_at stamped');

    _logger.info(
      '[discovery.autoDiscover] ✓ DONE — final keys: ${mappedFields.keys.toList()}',
    );
    _logger.info(
      '[discovery.autoDiscover] name=${mappedFields['name']} soundcloud_url=${mappedFields['soundcloud_url']}',
    );
    _logger.info(
      '[discovery.autoDiscover] identity_confidence=${mappedFields['identity_confidence']} coverage_level=${mappedFields['coverage_level']}',
    );

    return mappedFields;
  }

  Future<Map<String, dynamic>> _runLlmIdentityWalk(
    String name,
    String seedContext,
  ) async {
    final prompt =
        '''Identify the official online presence for music artist "$name".

CONTEXT:
$seedContext

NETWORK RELATIONAL REASONING:
- Follow breadcrumbs: if official links are missing from bios, compare track titles and locations across platforms to confirm identity.
- ALIAS REASONING: The artist's display name and platform handles may differ. The SoundCloud permalink (slug) is their actual username — it often matches their handle on other platforms even when the display name differs (e.g., permalink "vrecordings" → display name "Planet V"). Search for BOTH the display name and the permalink when finding links.
- ENTITY TYPE: Determine whether this entity is an artist/band (a person or group who makes music) or a label/organization (a record label or imprint that releases music by many artists). Labels typically have "Records", "Music", "Audio", or a collective noun in their name.
- Confirm if platforms (SoundCloud, Spotify, YouTube, Instagram) share the same "Metadata Fingerprint" (same song names, same label mention).

Return the following JSON ONLY:
{
  "soundcloudRss": {"url": "string or null"},
  "bandcampRss": {"url": "string or null"},
  "youtube": {"id": "handle or channelId or null"},
  "spotify": {"id": "Spotify artist ID or null"},
  "website": {"url": "string or null"},
  "entityType": "artist|band|label|organization|venue|brand|other",
  "streamingPlatforms": {
    "appleMusic": "Apple Music artist ID (from music.apple.com/artist/{id}) or null",
    "deezer": "Deezer artist ID (numeric, from deezer.com/artist/{id}) or null",
    "tidal": "TIDAL artist ID (numeric, from listen.tidal.com/artist/{id}) or null"
  },
  "passivePlatforms": {
    "instagram": "username or null",
    "twitter": "username or null",
    "twitch": "Twitch login/username or null"
  },
  "suggestedEdges": [
    {"targetName": "string", "relationship": "string", "sourceUrl": "string", "type": "EXPLICIT_BIO_LINK | AI_SUGGESTED"}
  ],
  "analysis": "Specific explanation of breadcrumbs found including alias resolution."
}''';

    print('');
    print('[XENE GEMINI] ▶▶▶ Sending request to gemini-2.5-flash for "$name"');
    print('[XENE GEMINI] Prompt length: ${prompt.length} chars');
    _logger.info(
      '[discovery._runLlmIdentityWalk] ▶ sending request to Gemini name="$name" keyIndex=${rotator.currentIndex}',
    );

    while (true) {
      try {
        final response = await rotator.client.models.generateContent(
          model: 'gemini-2.5-flash',
          request: GenerateContentRequest(
            contents: [Content.text(prompt)],
            tools: [Tool(googleSearch: GoogleSearch())],
          ),
        );

        print('[XENE GEMINI] ◀◀◀ Response received from Gemini');
        _logger.info('[discovery._runLlmIdentityWalk] ← Gemini responded');
        rotator.logUsage(_logger, 'discovery._runLlmIdentityWalk', response);

        final rawText = response.text ?? '';
        print('[XENE GEMINI] Raw response length: ${rawText.length} chars');
        _logger.info(
          '[discovery._runLlmIdentityWalk] raw preview: "${rawText.substring(0, rawText.length.clamp(0, 400))}"',
        );

        var text = rawText.trim();
        if (text.contains('```json')) {
          text = text.split('```json')[1].split('```')[0].trim();
        } else if (text.contains('```')) {
          text = text.split('```')[1].split('```')[0].trim();
        }

        if (text.isEmpty) {
          _logger.warning(
            '[discovery._runLlmIdentityWalk] ⚠ text is EMPTY after stripping — returning {}',
          );
          return {};
        }

        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          _logger.info(
            '[discovery._runLlmIdentityWalk] ✓ JSON decoded OK — keys: ${decoded.keys.toList()}',
          );
          return decoded;
        }
        _logger.warning(
          '[discovery._runLlmIdentityWalk] ⚠ decoded JSON is not a Map — returning {}',
        );
        return {};
      } catch (e, st) {
        final safeError = _redactSensitiveText(e);
        if (GeminiKeyRotator.isQuotaError(e)) {
          _logger.warning(
            '[discovery._runLlmIdentityWalk] Quota on key ${rotator.currentIndex}: $safeError',
          );
          if (!rotator.rotate()) {
            _logger.warning(
              '[discovery._runLlmIdentityWalk] All keys exhausted — returning {}',
            );
            return {};
          }
          // Loop continues with next key
        } else {
          print(
            '[XENE GEMINI] LLM CALL THREW AN EXCEPTION for "$name": $safeError',
          );
          _logger.warning(
            '[discovery._runLlmIdentityWalk] Non-quota error for "$name": $safeError',
          );
          _logger.warning(
            '[discovery._runLlmIdentityWalk] stacktrace: ${_redactSensitiveText(st)}',
          );
          return {};
        }
      }
    }
  }

  Future<Map<String, dynamic>> _runOpenRouterFallback(
    String name,
    String seedContext,
  ) async {
    final apiKey = Platform.environment['OPENROUTER_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      print(
        '[XENE OPENROUTER] *** FALLBACK SKIPPED — OPENROUTER_API_KEY not set ***',
      );
      _logger.warning(
        '[discovery._runOpenRouterFallback] OPENROUTER_API_KEY not set — OpenRouter disabled',
      );
      return {};
    }

    print('');
    print('[XENE OPENROUTER] ▶▶▶ Calling OpenRouter fallback for "$name"');
    _logger.info(
      '[discovery._runOpenRouterFallback] ▶ calling OpenRouter for "$name"',
    );

    final prompt =
        '''Identify the official online presence for music artist "$name".

CONTEXT:
$seedContext

NETWORK RELATIONAL REASONING:
- Follow breadcrumbs: if official links are missing from bios, compare track titles and locations across platforms to confirm identity.
- ALIAS REASONING: The artist's display name and platform handles may differ. The SoundCloud permalink (slug) is their actual username — it often matches their handle on other platforms even when the display name differs (e.g., permalink "vrecordings" → display name "Planet V"). Search for BOTH the display name and the permalink when finding links.
- ENTITY TYPE: Determine whether this entity is an artist/band (a person or group who makes music) or a label/organization (a record label or imprint that releases music by many artists). Labels typically have "Records", "Music", "Audio", or a collective noun in their name.
- Confirm if platforms (SoundCloud, Spotify, YouTube, Instagram) share the same "Metadata Fingerprint" (same song names, same label mention).

Return the following JSON ONLY:
{
  "soundcloudRss": {"url": "string or null"},
  "bandcampRss": {"url": "string or null"},
  "youtube": {"id": "handle or channelId or null"},
  "spotify": {"id": "Spotify artist ID or null"},
  "website": {"url": "string or null"},
  "entityType": "artist|band|label|organization|venue|brand|other",
  "streamingPlatforms": {
    "appleMusic": "Apple Music artist ID (from music.apple.com/artist/{id}) or null",
    "deezer": "Deezer artist ID (numeric, from deezer.com/artist/{id}) or null",
    "tidal": "TIDAL artist ID (numeric, from listen.tidal.com/artist/{id}) or null"
  },
  "passivePlatforms": {
    "instagram": "username or null",
    "twitter": "username or null",
    "twitch": "Twitch login/username or null"
  },
  "suggestedEdges": [
    {"targetName": "string", "relationship": "string", "sourceUrl": "string", "type": "EXPLICIT_BIO_LINK | AI_SUGGESTED"}
  ],
  "analysis": "Specific explanation of breadcrumbs found including alias resolution."
}''';

    try {
      final dio = Dio();
      final response = await dio.post<Map<String, dynamic>>(
        'https://openrouter.ai/api/v1/chat/completions',
        data: {
          'model': 'openrouter/free',
          'messages': [
            {
              'role': 'system',
              'content': 'Return only valid JSON. No markdown. No prose.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 1024,
          'provider': {'allow_fallbacks': true},
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'X-Title': 'Xene Artist Aggregator',
          },
        ),
      );

      print(
        '[XENE OPENROUTER] ◀◀◀ Response received — status=${response.statusCode}',
      );
      _logger.info(
        '[discovery._runOpenRouterFallback] ← status=${response.statusCode}',
      );

      final choices = response.data?['choices'] as List?;
      final firstChoice = choices == null || choices.isEmpty
          ? null
          : choices.first;
      final message = firstChoice is Map ? firstChoice['message'] : null;
      final content = message is Map
          ? _contentToString(message['content'])
          : '';
      _logger.info(
        '[discovery._runOpenRouterFallback] content length=${content.length}',
      );

      if (content.isEmpty) {
        _logger.warning(
          '[discovery._runOpenRouterFallback] empty response shape: ${_summarizeOpenRouterResponse(response.data)}',
        );
        _logger.warning(
          '[discovery._runOpenRouterFallback] ⚠ empty content — returning {}',
        );
        return {};
      }

      var text = content.trim();
      if (text.contains('```json')) {
        text = text.split('```json')[1].split('```')[0].trim();
      } else if (text.contains('```')) {
        text = text.split('```')[1].split('```')[0].trim();
      }

      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        print(
          '[XENE OPENROUTER] ✓ JSON decoded OK — keys: ${decoded.keys.toList()}',
        );
        _logger.info(
          '[discovery._runOpenRouterFallback] ✓ decoded ${decoded.keys.length} fields',
        );
        return decoded;
      }
      _logger.warning(
        '[discovery._runOpenRouterFallback] ⚠ decoded is not a Map — returning {}',
      );
      return {};
    } catch (e, st) {
      final safeError = _redactSensitiveText(e);
      print(
        '[XENE OPENROUTER] OpenRouter fallback THREW for "$name": $safeError',
      );
      _logger.warning(
        '[discovery._runOpenRouterFallback] OpenRouter call failed for "$name": $safeError',
      );
      _logger.warning(
        '[discovery._runOpenRouterFallback] stacktrace: ${_redactSensitiveText(st)}',
      );
      return {};
    }
  }

  Future<Map<String, dynamic>> _runNvidiaFallback(
    String name,
    String seedContext,
  ) async {
    final apiKey = Platform.environment['NVIDIA_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      print('[XENE NVIDIA] *** FALLBACK SKIPPED - NVIDIA_API_KEY not set ***');
      _logger.warning(
        '[discovery._runNvidiaFallback] NVIDIA_API_KEY not set - NVIDIA disabled',
      );
      return {};
    }

    print('');
    print('[XENE NVIDIA] Calling NVIDIA fallback for "$name"');
    _logger.info('[discovery._runNvidiaFallback] calling NVIDIA for "$name"');

    final prompt =
        '''Identify the official online presence for music artist "$name".

CONTEXT:
$seedContext

NETWORK RELATIONAL REASONING:
- Follow breadcrumbs: if official links are missing from bios, compare track titles and locations across platforms to confirm identity.
- ALIAS REASONING: The artist's display name and platform handles may differ. The SoundCloud permalink (slug) is their actual username - it often matches their handle on other platforms even when the display name differs (e.g., permalink "vrecordings" -> display name "Planet V"). Search for BOTH the display name and the permalink when finding links.
- ENTITY TYPE: Determine whether this entity is an artist/band (a person or group who makes music) or a label/organization (a record label or imprint that releases music by many artists). Labels typically have "Records", "Music", "Audio", or a collective noun in their name.
- Confirm if platforms (SoundCloud, Spotify, YouTube, Instagram) share the same "Metadata Fingerprint" (same song names, same label mention).

Return the following JSON ONLY:
{
  "soundcloudRss": {"url": "string or null"},
  "bandcampRss": {"url": "string or null"},
  "youtube": {"id": "handle or channelId or null"},
  "spotify": {"id": "Spotify artist ID or null"},
  "website": {"url": "string or null"},
  "entityType": "artist|band|label|organization|venue|brand|other",
  "streamingPlatforms": {
    "appleMusic": "Apple Music artist ID (from music.apple.com/artist/{id}) or null",
    "deezer": "Deezer artist ID (numeric, from deezer.com/artist/{id}) or null",
    "tidal": "TIDAL artist ID (numeric, from listen.tidal.com/artist/{id}) or null"
  },
  "passivePlatforms": {
    "instagram": "username or null",
    "twitter": "username or null",
    "twitch": "Twitch login/username or null"
  },
  "suggestedEdges": [
    {"targetName": "string", "relationship": "string", "sourceUrl": "string", "type": "EXPLICIT_BIO_LINK | AI_SUGGESTED"}
  ],
  "analysis": "Specific explanation of breadcrumbs found including alias resolution."
}''';

    try {
      final dio = Dio();
      final response = await dio.post<Map<String, dynamic>>(
        'https://integrate.api.nvidia.com/v1/chat/completions',
        data: {
          'model':
              Platform.environment['NVIDIA_MODEL'] ??
              'meta/llama-3.3-70b-instruct',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.2,
          'top_p': 0.7,
          'max_tokens': 1024,
          'stream': false,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      print('[XENE NVIDIA] Response received - status=${response.statusCode}');
      _logger.info(
        '[discovery._runNvidiaFallback] status=${response.statusCode}',
      );

      final choices = response.data?['choices'] as List?;
      final firstChoice = choices == null || choices.isEmpty
          ? null
          : choices.first;
      final message = firstChoice is Map ? firstChoice['message'] : null;
      final content = message is Map
          ? message['content']?.toString() ?? ''
          : '';
      _logger.info(
        '[discovery._runNvidiaFallback] content length=${content.length}',
      );

      if (content.isEmpty) {
        _logger.warning(
          '[discovery._runNvidiaFallback] empty content - returning {}',
        );
        return {};
      }

      var text = content.trim();
      if (text.contains('```json')) {
        text = text.split('```json')[1].split('```')[0].trim();
      } else if (text.contains('```')) {
        text = text.split('```')[1].split('```')[0].trim();
      }

      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        print('[XENE NVIDIA] JSON decoded OK - keys: ${decoded.keys.toList()}');
        _logger.info(
          '[discovery._runNvidiaFallback] decoded ${decoded.keys.length} fields',
        );
        return decoded;
      }
      _logger.warning(
        '[discovery._runNvidiaFallback] decoded is not a Map - returning {}',
      );
      return {};
    } catch (e, st) {
      print('[XENE NVIDIA] NVIDIA fallback THREW for "$name": $e');
      _logger.warning(
        '[discovery._runNvidiaFallback] NVIDIA call failed for "$name": $e',
      );
      _logger.warning('[discovery._runNvidiaFallback] stacktrace: $st');
      return {};
    }
  }
}
