import 'dart:io';

import 'package:googleai_dart/googleai_dart.dart';
import 'package:logging/logging.dart';

import 'api_analytics_service.dart';

final _logger = Logger('GeminiKeyRotator');

/// Manages a pool of Gemini API keys, rotating to the next on quota exhaustion.
/// One shared instance is injected into all services so burning key #1 in
/// discovery automatically skips it in press scout too.
///
/// Also accumulates in-memory usage stats exposed via [stats] for the monitor
/// dashboard. Stats reset on server restart — this is intentional (dev tooling).
class GeminiKeyRotator {
  GeminiKeyRotator({ApiAnalyticsService? analytics}) : _analytics = analytics {
    _clients = _buildClients();
    if (_clients.isEmpty) {
      _logger.severe('[rotator] No Gemini API keys found in environment');
    } else {
      _logger.info('[rotator] Loaded ${_clients.length} Gemini key(s)');
    }
  }

  late final List<GoogleAIClient> _clients;
  final ApiAnalyticsService? _analytics;
  int _currentIndex = 0;

  // ── Session stats (in-memory, resets on server restart) ──────────────────
  final DateTime _startedAt = DateTime.now().toUtc();
  int _rotationCount = 0;
  final _perKey = <int, _KeyStats>{};
  final _recentCalls = <_CallEntry>[];
  final _onboarding = _BucketStats(); // discovery + press_scout.single
  final _upkeep = _BucketStats(); // press_scout.batch(N)
  static const _kMaxRecentCalls = 50;
  // ─────────────────────────────────────────────────────────────────────────

  bool get hasKeys => _clients.isNotEmpty;
  int get keyCount => _clients.length;
  int get currentIndex => _currentIndex;

  /// The currently active client. Throws if no keys are configured.
  GoogleAIClient get client {
    if (_clients.isEmpty) throw StateError('No Gemini API keys configured');
    return _clients[_currentIndex];
  }

  /// Advances to the next key. Returns true if a new key is available,
  /// false if all keys are exhausted (caller should fall to OpenRouter).
  bool rotate() {
    if (_currentIndex + 1 >= _clients.length) {
      _logger.warning(
        '[rotator] All ${_clients.length} Gemini key(s) exhausted — falling to OpenRouter',
      );
      return false;
    }
    _currentIndex++;
    _rotationCount++;
    _logger.info('[rotator] Rotated to Gemini key index=$_currentIndex');
    return true;
  }

  /// Resets to the first key. Call at the start of each nightly batch run
  /// so quota accumulates against fresh daily limits, not yesterday's state.
  void reset() {
    _currentIndex = 0;
    _logger.info('[rotator] Key index reset to 0 for new batch');
  }

  /// Logs token usage and grounding status, and records to in-memory stats.
  ///
  /// Call bucket routing:
  ///   context starts with "press_scout.batch" → upkeep (scheduled)
  ///   everything else                         → on-boarding (user-triggered)
  void logUsage(
    Logger logger,
    String context,
    GenerateContentResponse response,
  ) {
    final usage = response.usageMetadata;
    final grounded =
        response.candidates?.any(
          (c) => c.groundingMetadata?.groundingChunks?.isNotEmpty == true,
        ) ??
        false;
    final inTokens = usage?.promptTokenCount ?? 0;
    final outTokens = usage?.candidatesTokenCount ?? 0;

    logger.info(
      '[$context] gemini usage '
      'in=$inTokens out=$outTokens total=${usage?.totalTokenCount ?? 0} '
      'grounded=$grounded keyIndex=$_currentIndex',
    );

    // Per-key accumulation
    final keyStats = _perKey.putIfAbsent(_currentIndex, _KeyStats.new);
    keyStats.calls++;
    keyStats.inputTokens += inTokens;
    keyStats.outputTokens += outTokens;
    if (grounded) keyStats.groundedCalls++;

    // Bucket routing
    final bucket = context.startsWith('press_scout.batch')
        ? _upkeep
        : _onboarding;
    bucket.calls++;
    bucket.inputTokens += inTokens;
    bucket.outputTokens += outTokens;
    if (grounded) bucket.groundedCalls++;

    _analytics?.recordLlmCall(
      provider: 'gemini',
      context: context,
      inputTokens: inTokens,
      outputTokens: outTokens,
      grounded: grounded,
      keyIndex: _currentIndex,
    );

    // Ring buffer: keep last 50 calls
    if (_recentCalls.length >= _kMaxRecentCalls) _recentCalls.removeAt(0);
    _recentCalls.add(
      _CallEntry(
        timestamp: DateTime.now().toUtc(),
        context: context,
        inputTokens: inTokens,
        outputTokens: outTokens,
        grounded: grounded,
        keyIndex: _currentIndex,
      ),
    );
  }

  void logQuotaError(String context, Object error) {
    _analytics?.recordLlmError(
      provider: 'gemini',
      context: context,
      error: error,
      throttled: true,
    );
  }

  /// Returns a JSON-serialisable snapshot of all in-memory stats.
  /// Consumed by `GET /monitor`.
  Map<String, dynamic> get stats => {
    'gemini': {
      'keyCount': keyCount,
      'currentKeyIndex': _currentIndex,
      'rotations': _rotationCount,
      'hasKeys': hasKeys,
    },
    'onboarding': _bucketToMap(_onboarding),
    'upkeep': _bucketToMap(_upkeep),
    'perKey': [
      for (final e in _perKey.entries)
        {
          'keyIndex': e.key,
          'calls': e.value.calls,
          'inputTokens': e.value.inputTokens,
          'outputTokens': e.value.outputTokens,
          'groundedCalls': e.value.groundedCalls,
        },
    ],
    'recentCalls': _recentCalls.reversed
        .map(
          (c) => {
            'timestamp': c.timestamp.toIso8601String(),
            'context': c.context,
            'inputTokens': c.inputTokens,
            'outputTokens': c.outputTokens,
            'grounded': c.grounded,
            'keyIndex': c.keyIndex,
          },
        )
        .toList(),
    'startedAt': _startedAt.toIso8601String(),
  };

  /// Returns true if [e] looks like a Gemini quota or rate-limit error.
  static bool isQuotaError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('resource_exhausted') ||
        msg.contains('429') ||
        msg.contains('quota') ||
        msg.contains('ratelimitexceeded') ||
        msg.contains('too many requests');
  }

  Map<String, dynamic> _bucketToMap(_BucketStats b) => {
    'calls': b.calls,
    'inputTokens': b.inputTokens,
    'outputTokens': b.outputTokens,
    'groundedCalls': b.groundedCalls,
    'estimatedCostUsd': (b.groundedCalls * 0.035).toStringAsFixed(3),
  };

  List<GoogleAIClient> _buildClients() {
    final keys = <String>[];

    // Primary: comma-separated keys in one env var (no renaming required).
    // GEMINI_API_KEY=AIzaKEY1,AIzaKEY2,AIzaKEY3
    final raw =
        Platform.environment['GEMINI_API_KEY'] ??
        Platform.environment['GOOGLE_API_KEY'] ??
        '';
    keys.addAll(raw.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty));

    // Alternative: GEMINI_API_KEY_1, GEMINI_API_KEY_2, ...
    // Only checked if comma-separated var is absent or single-valued.
    if (keys.length <= 1) {
      for (var i = 1; i <= 20; i++) {
        final key = Platform.environment['GEMINI_API_KEY_$i'];
        if (key == null || key.isEmpty) break;
        if (!keys.contains(key)) keys.add(key);
      }
    }

    return [
      for (final k in keys)
        GoogleAIClient(
          config: GoogleAIConfig.googleAI(authProvider: ApiKeyProvider(k)),
        ),
    ];
  }
}

// ── Private data classes ───────────────────────────────────────────────────

class _BucketStats {
  int calls = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  int groundedCalls = 0;
}

class _KeyStats {
  int calls = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  int groundedCalls = 0;
}

class _CallEntry {
  const _CallEntry({
    required this.timestamp,
    required this.context,
    required this.inputTokens,
    required this.outputTokens,
    required this.grounded,
    required this.keyIndex,
  });
  final DateTime timestamp;
  final String context;
  final int inputTokens;
  final int outputTokens;
  final bool grounded;
  final int keyIndex;
}
