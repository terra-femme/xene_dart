import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:xene_domain/xene_domain.dart';

import 'dio_provider.dart';

final _logger = Logger('daily_inbox_provider');

/// Flips to true the first time the inbox sheet is opened this session.
final inboxReadProvider = StateProvider<bool>((ref) => false);

/// Fetches and caches today's daily inbox digest for the session.
/// Not autoDispose — the digest is stable for 24h, no need to refetch on nav.
final dailyInboxProvider = FutureProvider<DailyInboxMessage?>((ref) async {
  final dio = ref.watch(authenticatedDioProvider);
  _logger.info('[inbox] fetching daily digest');

  try {
    final res = await dio.get<Map<String, dynamic>>('/inbox/daily');
    if (res.statusCode == 204 || res.data == null) {
      _logger.info('[inbox] no digest available (204)');
      return null;
    }
    final msg = DailyInboxMessage.fromJson(res.data!);
    _logger.info(
      '[inbox] loaded digest date=${msg.date} stations=${msg.stations.length} expires=${msg.expiresAt}',
    );
    return msg.isActive ? msg : null;
  } catch (e) {
    _logger.warning('[inbox] fetch error: $e');
    return null;
  }
});
