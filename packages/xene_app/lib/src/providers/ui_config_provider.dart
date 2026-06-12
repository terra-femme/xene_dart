import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'dio_provider.dart';
import '../theme/xene_theme.dart';

final _logger = Logger('ui_config');

/// Remote design-token config fetched from GET /config on startup.
///
/// Changes to primary_color, teal_color, feed_heading, or feed_scroll_speed
/// in the Supabase app_ui_config table take effect on next app launch
/// without a binary update.
@immutable
class UiConfig {
  const UiConfig({
    required this.primaryColor,
    required this.tealColor,
    required this.feedHeading,
    required this.feedScrollSpeed,
    this.navLabels,
  });

  final Color primaryColor;
  final Color tealColor;

  /// The large heading text on the feed screen (default: "JUST DROPPED").
  final String feedHeading;

  /// Multiplier over the base crawl speed of 0.043 px/ms.
  /// 1.0 = original speed. 0.5 = half speed. 2.0 = double speed.
  final double feedScrollSpeed;

  /// Optional map of route → label overrides, e.g. {"/articles": "EDITORIAL"}.
  /// Null means use compiled-in defaults.
  final Map<String, String>? navLabels;

  static UiConfig get defaults => const UiConfig(
    primaryColor: XeneTheme.orange,
    tealColor: XeneTheme.teal,
    feedHeading: 'JUST DROPPED',
    feedScrollSpeed: 1.0,
  );

  factory UiConfig.fromJson(Map<String, dynamic> json) {
    return UiConfig(
      primaryColor: _hexToColor(
        json['primary_color'] as String?,
        XeneTheme.orange,
      ),
      tealColor: _hexToColor(json['teal_color'] as String?, XeneTheme.teal),
      feedHeading: (json['feed_heading'] as String?)?.trim().isNotEmpty == true
          ? (json['feed_heading'] as String).trim().toUpperCase()
          : 'JUST DROPPED',
      feedScrollSpeed:
          (json['feed_scroll_speed'] as num?)?.toDouble().clamp(0.1, 5.0) ??
          1.0,
      navLabels: (json['nav_labels'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v.toString()),
      ),
    );
  }
}

Color _hexToColor(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) return fallback;
  final h = hex.startsWith('#') ? hex.substring(1) : hex;
  if (h.length != 6) return fallback;
  final value = int.tryParse('FF$h', radix: 16);
  return value != null ? Color(value) : fallback;
}

/// Fetched once on startup. keepAlive so the config survives provider refreshes.
final uiConfigProvider = FutureProvider<UiConfig>((ref) async {
  final dio = ref.watch(authenticatedDioProvider);
  try {
    _logger.info('[ui_config] fetching /config');
    final response = await dio.get<Map<String, dynamic>>('/config');
    final data = response.data;
    if (data == null) {
      _logger.warning('[ui_config] null response — using defaults');
      return UiConfig.defaults;
    }
    final config = UiConfig.fromJson(data);
    _logger.info(
      '[ui_config] loaded primary=${_colorHex(config.primaryColor)} '
      'teal=${_colorHex(config.tealColor)} heading="${config.feedHeading}" '
      'speed=${config.feedScrollSpeed}',
    );
    return config;
  } catch (e) {
    _logger.warning('[ui_config] fetch failed — using defaults: $e');
    return UiConfig.defaults;
  }
});

String _colorHex(Color c) {
  final argb = c.toARGB32();
  return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
