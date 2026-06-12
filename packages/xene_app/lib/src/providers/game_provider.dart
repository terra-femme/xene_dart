import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:xene_domain/xene_domain.dart';
import 'dio_provider.dart';

final _logger = Logger('game_provider');

// ── Username ──────────────────────────────────────────────────────────────────

final usernameProvider = FutureProvider.autoDispose<String?>((ref) async {
  final dio = ref.watch(authenticatedDioProvider);
  try {
    final res = await dio.get('/game/profile/username');
    return res.data['username'] as String?;
  } catch (e) {
    _logger.warning('[game] usernameProvider error: $e');
    return null;
  }
});

// ── Parties list ──────────────────────────────────────────────────────────────

class GamePartiesNotifier extends AsyncNotifier<List<PartyPreview>> {
  @override
  Future<List<PartyPreview>> build() => _fetch();

  Future<List<PartyPreview>> _fetch() async {
    final dio = ref.read(authenticatedDioProvider);
    _logger.info('[game] fetching parties');
    final res = await dio.get<List<dynamic>>('/game/parties');
    final list = res.data ?? [];
    _logger.info('[game] got ${list.length} parties');
    return list
        .cast<Map<String, dynamic>>()
        .map(PartyPreview.fromJson)
        .toList();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<PartyPreview?> createParty(String name) async {
    try {
      final dio = ref.read(authenticatedDioProvider);
      final res = await dio.post<Map<String, dynamic>>(
        '/game/parties',
        data: {'name': name},
      );
      _logger.info('[game] createParty response: ${res.data}');
      await refresh();
      return state.valueOrNull?.firstOrNull;
    } on DioException catch (e) {
      _logger.warning('[game] createParty error: ${e.response?.data}');
      rethrow;
    }
  }

  Future<void> joinParty(String inviteCode) async {
    try {
      final dio = ref.read(authenticatedDioProvider);
      await dio.post('/game/join/$inviteCode');
      _logger.info('[game] joinParty code=$inviteCode');
      await refresh();
    } on DioException catch (e) {
      _logger.warning('[game] joinParty error: ${e.response?.data}');
      rethrow;
    }
  }

  Future<void> leaveParty(String partyId) async {
    try {
      final dio = ref.read(authenticatedDioProvider);
      await dio.delete('/game/parties/$partyId/leave');
      _logger.info('[game] leaveParty partyId=$partyId');
      await refresh();
    } on DioException catch (e) {
      _logger.warning('[game] leaveParty error: ${e.response?.data}');
      rethrow;
    }
  }
}

final gamePartiesProvider =
    AsyncNotifierProvider<GamePartiesNotifier, List<PartyPreview>>(
      GamePartiesNotifier.new,
    );

// ── Party detail ──────────────────────────────────────────────────────────────

final partyDetailProvider = FutureProvider.family
    .autoDispose<PartyDetail?, String>((ref, partyId) async {
      final dio = ref.watch(authenticatedDioProvider);
      _logger.info('[game] fetching detail partyId=$partyId');
      try {
        final res = await dio.get<Map<String, dynamic>>(
          '/game/parties/$partyId',
        );
        return PartyDetail.fromJson(res.data!);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) return null;
        rethrow;
      }
    });

// ── Weekly tracks ─────────────────────────────────────────────────────────────

class WeeklyTracksNotifier
    extends FamilyAsyncNotifier<WeeklyTracksState, String> {
  @override
  Future<WeeklyTracksState> build(String partyId) => _fetch(partyId);

  Future<WeeklyTracksState> _fetch(String partyId, {String? week}) async {
    final dio = ref.read(authenticatedDioProvider);
    final queryWeek = week ?? _currentWeekStart();
    _logger.info('[game] fetchWeeklyTracks partyId=$partyId week=$queryWeek');
    final res = await dio.get<Map<String, dynamic>>(
      '/game/parties/$partyId/tracks',
      queryParameters: {'week': queryWeek},
    );
    final data = res.data!;
    final memberTracks = (data['members'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(MemberTracks.fromJson)
        .toList();
    return WeeklyTracksState(
      weekStart: data['week_start'] as String,
      isWeekClosed: data['is_week_closed'] as bool? ?? false,
      isResultsVisible: data['is_results_visible'] as bool? ?? false,
      memberTracks: memberTracks,
    );
  }

  Future<void> refresh({String? week}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(arg, week: week));
  }

  Future<void> submitTrack(Map<String, dynamic> track) async {
    final dio = ref.read(authenticatedDioProvider);
    await dio.post('/game/parties/$arg/tracks', data: track);
    _logger.info(
      '[game] submitTrack partyId=$arg trackId=${track['sc_track_id']}',
    );
    await refresh();
    // Party card count is stale without this — the list screen caches it.
    ref.read(gamePartiesProvider.notifier).refresh();
  }

  Future<void> deleteTrack(String trackId) async {
    final dio = ref.read(authenticatedDioProvider);
    await dio.delete('/game/parties/$arg/tracks/$trackId');
    _logger.info('[game] deleteTrack partyId=$arg trackId=$trackId');
    await refresh();
    ref.read(gamePartiesProvider.notifier).refresh();
  }

  Future<String?> exportToScPlaylist(String weekStart) async {
    final dio = ref.read(authenticatedDioProvider);
    _logger.info('[game] exportToScPlaylist partyId=$arg week=$weekStart');
    try {
      final res = await dio.post<Map<String, dynamic>>(
        '/game/parties/$arg/export_sc',
        data: {'week': weekStart},
      );
      _logger.info('[game] exportToScPlaylist response: ${res.data}');
      return res.data?['playlist_url'] as String?;
    } on DioException catch (e) {
      _logger.warning(
        '[game] exportToScPlaylist HTTP error: '
        'status=${e.response?.statusCode} body=${e.response?.data}',
      );
      rethrow;
    }
  }
}

final weeklyTracksProvider =
    AsyncNotifierProvider.family<
      WeeklyTracksNotifier,
      WeeklyTracksState,
      String
    >(WeeklyTracksNotifier.new);

class WeeklyTracksState {
  const WeeklyTracksState({
    required this.weekStart,
    required this.isWeekClosed,
    required this.isResultsVisible,
    required this.memberTracks,
  });

  final String weekStart;
  final bool isWeekClosed;
  final bool isResultsVisible;
  final List<MemberTracks> memberTracks;

  /// True when this week's data is the live/current week.
  /// Submission is open the entire current week, regardless of isWeekClosed.
  bool get isCurrentWeek => weekStart == _currentWeekStart();
}

// ── Votes ─────────────────────────────────────────────────────────────────────

class WeekVotesNotifier extends FamilyAsyncNotifier<WeekVotes, String> {
  @override
  Future<WeekVotes> build(String partyId) => _fetch(partyId);

  Future<WeekVotes> _fetch(String partyId, {String? week}) async {
    final dio = ref.read(authenticatedDioProvider);
    final queryWeek = week ?? _currentWeekStart();
    _logger.info('[game] fetchVotes partyId=$partyId week=$queryWeek');
    final res = await dio.get<Map<String, dynamic>>(
      '/game/parties/$partyId/votes',
      queryParameters: {'week': queryWeek},
    );
    return WeekVotes.fromJson(res.data!);
  }

  Future<void> castVote(String votedForId, {String? week}) async {
    final dio = ref.read(authenticatedDioProvider);
    final voteWeek = week ?? _currentWeekStart();
    await dio.post(
      '/game/parties/$arg/votes',
      data: {'voted_for_id': votedForId, 'week_start': voteWeek},
    );
    _logger.info('[game] castVote partyId=$arg for=$votedForId');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(arg, week: voteWeek));
  }

  Future<void> refresh({String? week}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(arg, week: week));
  }
}

final weekVotesProvider =
    AsyncNotifierProvider.family<WeekVotesNotifier, WeekVotes, String>(
      WeekVotesNotifier.new,
    );

// ── Weekly scene ─────────────────────────────────────────────────────────────

/// The active scene text for the current week. Null when no scene is set.
/// Global — the same scene applies to every party this week.
final weekSceneProvider = FutureProvider.autoDispose<String?>((ref) async {
  final dio = ref.watch(authenticatedDioProvider);
  final week = _currentWeekStart();
  _logger.info('[game] fetchWeekScene week=$week');
  try {
    final res = await dio.get<Map<String, dynamic>>(
      '/game/scene',
      queryParameters: {'week': week},
    );
    return res.data?['text'] as String?;
  } catch (e) {
    _logger.warning('[game] weekSceneProvider error: $e');
    return null;
  }
});

// ── Party weeks (archive navigation) ─────────────────────────────────────────

final partyWeeksProvider = FutureProvider.family
    .autoDispose<List<String>, String>((ref, partyId) async {
      final dio = ref.watch(authenticatedDioProvider);
      _logger.info('[game] fetchPartyWeeks partyId=$partyId');
      final res = await dio.get<List<dynamic>>('/game/parties/$partyId/weeks');
      return (res.data ?? []).cast<String>();
    });

// ── Archive tracks (past weeks, read-only) ────────────────────────────────────

/// Family arg: (partyId, weekStart) — both strings. Records implement == / hashCode.
final archiveTracksProvider = FutureProvider.family
    .autoDispose<WeeklyTracksState, (String, String)>((ref, args) async {
      final partyId = args.$1;
      final week = args.$2;
      final dio = ref.watch(authenticatedDioProvider);
      _logger.info('[game] fetchArchive partyId=$partyId week=$week');
      final res = await dio.get<Map<String, dynamic>>(
        '/game/parties/$partyId/tracks',
        queryParameters: {'week': week},
      );
      final data = res.data!;
      return WeeklyTracksState(
        weekStart: data['week_start'] as String,
        isWeekClosed: true,
        isResultsVisible: true,
        memberTracks: (data['members'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(MemberTracks.fromJson)
            .toList(),
      );
    });

// ── Leaderboard ───────────────────────────────────────────────────────────────

final leaderboardProvider = FutureProvider.family
    .autoDispose<List<LeaderboardEntry>, String>((ref, partyId) async {
      final dio = ref.watch(authenticatedDioProvider);
      _logger.info('[game] fetchLeaderboard partyId=$partyId');
      final res = await dio.get<List<dynamic>>('/game/parties/$partyId/scores');
      return (res.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(LeaderboardEntry.fromJson)
          .toList();
    });

// ── Weekly winners (for monthly progress widget) ──────────────────────────────

final weeklyWinnersProvider = FutureProvider.family
    .autoDispose<List<WeekWinner>, String>((ref, partyId) async {
      final dio = ref.watch(authenticatedDioProvider);
      _logger.info('[game] fetchWeeklyWinners partyId=$partyId');
      try {
        final res = await dio.get<List<dynamic>>(
          '/game/parties/$partyId/weekly_winners',
        );
        return (res.data ?? [])
            .cast<Map<String, dynamic>>()
            .map(WeekWinner.fromJson)
            .toList();
      } catch (e) {
        _logger.warning('[game] weeklyWinnersProvider error: $e');
        return [];
      }
    });

// ── SC track search ───────────────────────────────────────────────────────────

final scTrackSearchProvider = FutureProvider.family
    .autoDispose<List<ScTrackResult>, String>((ref, query) async {
      if (query.trim().isEmpty) return [];
      final dio = ref.watch(authenticatedDioProvider);
      _logger.info('[game] searchTracks q="$query"');
      final res = await dio.get<Map<String, dynamic>>(
        '/soundcloud/track_search',
        queryParameters: {'q': query.trim()},
      );
      final collection = (res.data?['collection'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      return collection.map(ScTrackResult.fromJson).toList();
    });

// ── Helpers ───────────────────────────────────────────────────────────────────

String _currentWeekStart() {
  const offsetHours = int.fromEnvironment('GAME_DEBUG_HOURS', defaultValue: 0);
  final now = DateTime.now().toUtc().add(const Duration(hours: offsetHours));
  final monday = now.subtract(Duration(days: now.weekday - 1));
  return '${monday.year.toString().padLeft(4, '0')}-'
      '${monday.month.toString().padLeft(2, '0')}-'
      '${monday.day.toString().padLeft(2, '0')}';
}
