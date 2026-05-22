import 'dart:math';
import 'package:logging/logging.dart';
import '../database.dart';

final _logger = Logger('GameService');

const _maxPartiesPerUser = 3;
const _maxTracksPerWeek = 5;
const _inviteCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

class GameService {
  GameService(this._db);

  final DatabaseService _db;

  // ── Week helpers ──────────────────────────────────────────────────────────

  /// Returns the date string ('YYYY-MM-DD') for the Monday that starts the
  /// current week (UTC).
  static String currentWeekStart() {
    final now = DateTime.now().toUtc();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return '${monday.year.toString().padLeft(4, '0')}-'
        '${monday.month.toString().padLeft(2, '0')}-'
        '${monday.day.toString().padLeft(2, '0')}';
  }

  /// Parses a 'YYYY-MM-DD' week_start string into a UTC DateTime.
  static DateTime _parseWeekStart(String s) {
    final parts = s.split('-');
    return DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// True if the voting + submission window has closed (past Friday 21:00 UTC).
  static bool isWeekClosed(String weekStart) {
    final monday = _parseWeekStart(weekStart);
    final friday = monday.add(const Duration(days: 4));
    final deadline = DateTime.utc(friday.year, friday.month, friday.day, 21);
    return DateTime.now().toUtc().isAfter(deadline);
  }

  /// True if results are visible (past Friday 21:05 UTC).
  static bool isResultsVisible(String weekStart) {
    final monday = _parseWeekStart(weekStart);
    final friday = monday.add(const Duration(days: 4));
    final reveal = DateTime.utc(friday.year, friday.month, friday.day, 21, 5);
    return DateTime.now().toUtc().isAfter(reveal);
  }

  // ── Username ──────────────────────────────────────────────────────────────

  Future<String?> getUsername(String userId) async {
    try {
      final row = await _db.client
          .from('profiles')
          .select('username')
          .eq('id', userId)
          .maybeSingle();
      return row?['username'] as String?;
    } catch (e) {
      _logger.warning('[game] getUsername error userId=$userId: $e');
      return null;
    }
  }

  /// Sets or updates the username for a user. Returns null on success, or an
  /// error string the caller can surface to the user.
  Future<String?> setUsername(String userId, String username) async {
    final trimmed = username.trim();
    if (trimmed.length < 3 || trimmed.length > 20) {
      return 'Username must be 3–20 characters';
    }
    final validChars = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!validChars.hasMatch(trimmed)) {
      return 'Only letters, numbers, and underscores allowed';
    }
    try {
      await _db.client
          .from('profiles')
          .update({
            'username': trimmed,
            'username_updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', userId);
      _logger.info('[game] setUsername: userId=$userId username=$trimmed');
      return null;
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('profiles_username_unique') ||
          msg.contains('unique') ||
          msg.contains('duplicate')) {
        return 'Username already taken';
      }
      _logger.severe('[game] setUsername error: $e');
      return 'Could not save username, please try again';
    }
  }

  // ── Party management ──────────────────────────────────────────────────────

  /// Creates a new party and adds the creator as the first member.
  /// Returns the full party row, or throws on failure.
  Future<Map<String, dynamic>> createParty(String userId, String name) async {
    _logger.info('[game] createParty userId=$userId name="$name"');
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 50) {
      throw ArgumentError('Party name must be 1–50 characters');
    }

    final count = await _partyCountForUser(userId);
    if (count >= _maxPartiesPerUser) {
      throw StateError('Maximum of $_maxPartiesPerUser parties per user');
    }

    final code = _generateInviteCode();
    final party = await _db.client
        .from('game_parties')
        .insert({'name': trimmed, 'created_by': userId, 'invite_code': code})
        .select()
        .single();

    await _db.client.from('party_members').insert({
      'party_id': party['id'],
      'user_id': userId,
    });

    _logger.info(
      '[game] createParty: created partyId=${party['id']} code=$code',
    );
    return party;
  }

  /// Joins an existing party by invite code.
  /// Throws [ArgumentError] if the code is invalid and [StateError] if caps are hit.
  Future<Map<String, dynamic>> joinParty(
    String userId,
    String inviteCode,
  ) async {
    _logger.info('[game] joinParty userId=$userId code=$inviteCode');
    final code = inviteCode.trim().toUpperCase();

    final party = await _db.client
        .from('game_parties')
        .select()
        .eq('invite_code', code)
        .eq('is_active', true)
        .maybeSingle();

    if (party == null) {
      throw ArgumentError('Invalid invite code');
    }

    final partyId = party['id'] as String;

    final alreadyMember = await _isMember(partyId, userId);
    if (alreadyMember) {
      return party;
    }

    final count = await _partyCountForUser(userId);
    if (count >= _maxPartiesPerUser) {
      throw StateError('Maximum of $_maxPartiesPerUser parties per user');
    }

    await _db.client.from('party_members').insert({
      'party_id': partyId,
      'user_id': userId,
    });

    _logger.info('[game] joinParty: userId=$userId joined partyId=$partyId');
    return party;
  }

  /// Removes a user from a party. The party persists even if all members leave.
  Future<void> leaveParty(String partyId, String userId) async {
    _logger.info('[game] leaveParty partyId=$partyId userId=$userId');
    await _db.client
        .from('party_members')
        .delete()
        .eq('party_id', partyId)
        .eq('user_id', userId);
  }

  /// Returns a summary list of parties the user belongs to, each enriched with
  /// member count and this week's submitted track count for the requesting user.
  Future<List<Map<String, dynamic>>> getUserParties(String userId) async {
    _logger.info('[game] getUserParties userId=$userId');
    try {
      final memberRows = await _db.client
          .from('party_members')
          .select('party_id')
          .eq('user_id', userId);

      final partyIds = List<Map<String, dynamic>>.from(
        memberRows,
      ).map((r) => r['party_id'] as String).toList();

      if (partyIds.isEmpty) return [];

      final parties = await _db.client
          .from('game_parties')
          .select()
          .inFilter('id', partyIds)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      final partyList = List<Map<String, dynamic>>.from(parties);
      final weekStart = currentWeekStart();

      final result = <Map<String, dynamic>>[];
      for (final party in partyList) {
        final partyId = party['id'] as String;

        final memberCount = await _db.client
            .from('party_members')
            .select('user_id')
            .eq('party_id', partyId);

        final myTracksThisWeek = await _db.client
            .from('party_tracks')
            .select('id')
            .eq('party_id', partyId)
            .eq('user_id', userId)
            .eq('week_start', weekStart);

        result.add({
          ...party,
          'member_count': (memberCount as List).length,
          'my_track_count_this_week': (myTracksThisWeek as List).length,
          'week_start': weekStart,
        });
      }

      _logger.info(
        '[game] getUserParties: ${result.length} parties for $userId',
      );
      return result;
    } catch (e) {
      _logger.severe('[game] getUserParties error: $e');
      return [];
    }
  }

  /// Returns party metadata + full member list with usernames.
  /// Returns null if partyId does not exist or the user is not a member.
  Future<Map<String, dynamic>?> getPartyDetail(
    String partyId,
    String userId,
  ) async {
    _logger.info('[game] getPartyDetail partyId=$partyId userId=$userId');
    try {
      final isMember = await _isMember(partyId, userId);
      if (!isMember) {
        _logger.warning(
          '[game] getPartyDetail: $userId is not a member of $partyId',
        );
        return null;
      }

      final party = await _db.client
          .from('game_parties')
          .select()
          .eq('id', partyId)
          .maybeSingle();
      if (party == null) return null;

      final memberRows = await _db.client
          .from('party_members')
          .select('user_id, joined_at')
          .eq('party_id', partyId)
          .order('joined_at');

      final memberList = List<Map<String, dynamic>>.from(memberRows);
      final userIds = memberList.map((r) => r['user_id'] as String).toList();

      final profiles = await _db.client
          .from('profiles')
          .select('id, username')
          .inFilter('id', userIds);

      final profileMap = <String, String?>{
        for (final p in List<Map<String, dynamic>>.from(profiles))
          p['id'] as String: p['username'] as String?,
      };

      final members = memberList.map((m) {
        final uid = m['user_id'] as String;
        return {
          'user_id': uid,
          'username': profileMap[uid] ?? 'Unknown',
          'joined_at': m['joined_at'],
          'is_me': uid == userId,
        };
      }).toList();

      return {...Map<String, dynamic>.from(party as Map), 'members': members};
    } catch (e) {
      _logger.severe('[game] getPartyDetail error: $e');
      return null;
    }
  }

  // ── Tracks ─────────────────────────────────────────────────────────────────

  /// Submits a SoundCloud track to the party for the current week.
  /// Throws [StateError] if the cap (5 tracks/week) is hit or the week is closed.
  Future<Map<String, dynamic>> submitTrack(
    String partyId,
    String userId,
    Map<String, dynamic> track,
  ) async {
    final weekStart = currentWeekStart();
    _logger.info(
      '[game] submitTrack partyId=$partyId userId=$userId '
      'trackId=${track['sc_track_id']} week=$weekStart',
    );

    if (isWeekClosed(weekStart)) {
      throw StateError('Submission window is closed for this week');
    }

    final isMember = await _isMember(partyId, userId);
    if (!isMember) throw StateError('User is not a member of this party');

    final existing = await _db.client
        .from('party_tracks')
        .select('id')
        .eq('party_id', partyId)
        .eq('user_id', userId)
        .eq('week_start', weekStart);

    if ((existing as List).length >= _maxTracksPerWeek) {
      throw StateError(
        'Maximum of $_maxTracksPerWeek tracks per week already submitted',
      );
    }

    final row = await _db.client
        .from('party_tracks')
        .insert({
          'party_id': partyId,
          'user_id': userId,
          'sc_track_id': track['sc_track_id'],
          'sc_track_url': track['sc_track_url'],
          'sc_title': track['sc_title'],
          'sc_artwork_url': track['sc_artwork_url'],
          'sc_duration_seconds': track['sc_duration_seconds'],
          'week_start': weekStart,
        })
        .select()
        .single();

    _logger.info('[game] submitTrack: inserted id=${row['id']}');
    return Map<String, dynamic>.from(row as Map);
  }

  /// Removes a track. Only the submitter can delete their own track, and only
  /// while the week is still open.
  Future<void> deleteTrack(String trackId, String userId) async {
    _logger.info('[game] deleteTrack trackId=$trackId userId=$userId');

    final track = await _db.client
        .from('party_tracks')
        .select()
        .eq('id', trackId)
        .maybeSingle();

    if (track == null) return;
    if (track['user_id'] != userId) {
      throw StateError("Cannot delete another user's track");
    }
    if (isWeekClosed(track['week_start'] as String)) {
      throw StateError('Cannot delete track after the week has closed');
    }

    await _db.client.from('party_tracks').delete().eq('id', trackId);
    _logger.info('[game] deleteTrack: deleted $trackId');
  }

  /// Returns all tracks for a party in a given week, grouped by member.
  /// Each entry: { member: {...}, tracks: [...] }
  Future<List<Map<String, dynamic>>> getWeeklyTracks(
    String partyId,
    String weekStart,
    String requestingUserId,
  ) async {
    _logger.info('[game] getWeeklyTracks partyId=$partyId week=$weekStart');
    try {
      final isMember = await _isMember(partyId, requestingUserId);
      if (!isMember) {
        _logger.warning('[game] getWeeklyTracks: not a member');
        return [];
      }

      final tracks = await _db.client
          .from('party_tracks')
          .select()
          .eq('party_id', partyId)
          .eq('week_start', weekStart)
          .order('submitted_at');

      final trackList = List<Map<String, dynamic>>.from(tracks as List);

      final memberRows = await _db.client
          .from('party_members')
          .select('user_id, joined_at')
          .eq('party_id', partyId)
          .order('joined_at');

      final memberList = List<Map<String, dynamic>>.from(memberRows as List);
      final userIds = memberList.map((r) => r['user_id'] as String).toList();

      final profiles = await _db.client
          .from('profiles')
          .select('id, username')
          .inFilter('id', userIds);

      final profileMap = <String, String?>{
        for (final p in List<Map<String, dynamic>>.from(profiles as List))
          p['id'] as String: p['username'] as String?,
      };

      final tracksByUser = <String, List<Map<String, dynamic>>>{};
      for (final t in trackList) {
        final uid = t['user_id'] as String;
        tracksByUser.putIfAbsent(uid, () => []).add(t);
      }

      return memberList.map((m) {
        final uid = m['user_id'] as String;
        return {
          'member': {
            'user_id': uid,
            'username': profileMap[uid] ?? 'Unknown',
            'is_me': uid == requestingUserId,
          },
          'tracks': tracksByUser[uid] ?? [],
        };
      }).toList();
    } catch (e) {
      _logger.severe('[game] getWeeklyTracks error: $e');
      return [];
    }
  }

  // ── Voting ─────────────────────────────────────────────────────────────────

  /// Casts (or updates) the voter's vote for the given week.
  /// Throws if the week is closed, the voter isn't a member, or they vote for themselves.
  Future<Map<String, dynamic>> castVote(
    String partyId,
    String voterId,
    String votedForId,
    String weekStart,
  ) async {
    _logger.info(
      '[game] castVote partyId=$partyId voter=$voterId for=$votedForId week=$weekStart',
    );

    if (isWeekClosed(weekStart)) {
      throw StateError('Voting window is closed for this week');
    }
    if (voterId == votedForId) {
      throw ArgumentError('Cannot vote for yourself');
    }

    final isMember = await _isMember(partyId, voterId);
    if (!isMember) throw StateError('Voter is not a member of this party');

    final targetMember = await _isMember(partyId, votedForId);
    if (!targetMember)
      throw ArgumentError('Voted-for user is not in this party');

    await _db.client.from('party_votes').upsert({
      'party_id': partyId,
      'voter_id': voterId,
      'voted_for_id': votedForId,
      'week_start': weekStart,
      'voted_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'party_id,voter_id,week_start');

    _logger.info(
      '[game] castVote: upserted vote voter=$voterId for=$votedForId',
    );
    return {
      'party_id': partyId,
      'voter_id': voterId,
      'voted_for_id': votedForId,
      'week_start': weekStart,
    };
  }

  /// Returns vote data for a week.
  ///
  /// During the active window (before Friday 21:05 UTC):
  ///   - Returns the requesting user's own vote (if cast)
  ///   - Returns a boolean map: userId → has this person cast a vote yet
  ///   - Does NOT reveal who got votes or tallies
  ///
  /// After results become visible (Friday 21:05 UTC+):
  ///   - Returns the full tally: userId → vote count
  Future<Map<String, dynamic>> getWeekVotes(
    String partyId,
    String weekStart,
    String requestingUserId,
  ) async {
    _logger.info(
      '[game] getWeekVotes partyId=$partyId week=$weekStart user=$requestingUserId',
    );
    try {
      final isMember = await _isMember(partyId, requestingUserId);
      if (!isMember) return {'error': 'not a member'};

      final votes = await _db.client
          .from('party_votes')
          .select('voter_id, voted_for_id')
          .eq('party_id', partyId)
          .eq('week_start', weekStart);

      final voteList = List<Map<String, dynamic>>.from(votes as List);

      final myVoteRow = voteList
          .where((v) => v['voter_id'] == requestingUserId)
          .firstOrNull;
      final myVote = myVoteRow?['voted_for_id'] as String?;
      final weekClosed = isWeekClosed(weekStart);
      final resultsVisible = isResultsVisible(weekStart);

      if (!resultsVisible) {
        final hasVoted = <String, bool>{};
        for (final v in voteList) {
          hasVoted[v['voter_id'] as String] = true;
        }
        return {
          'week_start': weekStart,
          'is_week_closed': weekClosed,
          'is_results_visible': false,
          'my_vote': myVote,
          'has_voted': hasVoted,
          'tally': null,
        };
      }

      final tally = <String, int>{};
      for (final v in voteList) {
        final uid = v['voted_for_id'] as String;
        tally[uid] = (tally[uid] ?? 0) + 1;
      }

      _logger.info(
        '[game] getWeekVotes: results visible, tally=${tally.length} entries',
      );
      return {
        'week_start': weekStart,
        'is_week_closed': weekClosed,
        'is_results_visible': true,
        'my_vote': myVote,
        'has_voted': {for (final v in voteList) v['voter_id'] as String: true},
        'tally': tally,
      };
    } catch (e) {
      _logger.severe('[game] getWeekVotes error: $e');
      return {};
    }
  }

  // ── Leaderboard ────────────────────────────────────────────────────────────

  /// Returns cumulative vote totals across all closed weeks, with win count.
  Future<List<Map<String, dynamic>>> getLeaderboard(
    String partyId,
    String requestingUserId,
  ) async {
    _logger.info('[game] getLeaderboard partyId=$partyId');
    try {
      final isMember = await _isMember(partyId, requestingUserId);
      if (!isMember) return [];

      final memberRows = await _db.client
          .from('party_members')
          .select('user_id, joined_at')
          .eq('party_id', partyId)
          .order('joined_at');

      final memberList = List<Map<String, dynamic>>.from(memberRows as List);
      final userIds = memberList.map((r) => r['user_id'] as String).toList();

      final profiles = await _db.client
          .from('profiles')
          .select('id, username')
          .inFilter('id', userIds);

      final profileMap = <String, String?>{
        for (final p in List<Map<String, dynamic>>.from(profiles as List))
          p['id'] as String: p['username'] as String?,
      };

      // Only count votes from closed weeks (results visible).
      final votes = await _db.client
          .from('party_votes')
          .select('voted_for_id, week_start')
          .eq('party_id', partyId);

      final voteList = List<Map<String, dynamic>>.from(votes as List);

      // Filter to only closed+revealed weeks.
      final closedVotes = voteList
          .where((v) => isResultsVisible(v['week_start'] as String))
          .toList();

      // Total votes per user.
      final totalVotes = <String, int>{};
      for (final v in closedVotes) {
        final uid = v['voted_for_id'] as String;
        totalVotes[uid] = (totalVotes[uid] ?? 0) + 1;
      }

      // Wins: group by week, find highest vote count per week.
      final votesByWeek = <String, Map<String, int>>{};
      for (final v in closedVotes) {
        final week = v['week_start'] as String;
        final uid = v['voted_for_id'] as String;
        votesByWeek.putIfAbsent(week, () => {});
        votesByWeek[week]![uid] = (votesByWeek[week]![uid] ?? 0) + 1;
      }

      final wins = <String, int>{};
      for (final weekTally in votesByWeek.values) {
        if (weekTally.isEmpty) continue;
        final maxVotes = weekTally.values.reduce((a, b) => a > b ? a : b);
        for (final entry in weekTally.entries) {
          if (entry.value == maxVotes) {
            wins[entry.key] = (wins[entry.key] ?? 0) + 1;
          }
        }
      }

      final leaderboard = memberList.map((m) {
        final uid = m['user_id'] as String;
        return {
          'user_id': uid,
          'username': profileMap[uid] ?? 'Unknown',
          'is_me': uid == requestingUserId,
          'total_votes': totalVotes[uid] ?? 0,
          'week_wins': wins[uid] ?? 0,
        };
      }).toList();

      leaderboard.sort((a, b) {
        final byVotes = (b['total_votes'] as int).compareTo(
          a['total_votes'] as int,
        );
        if (byVotes != 0) return byVotes;
        return (b['week_wins'] as int).compareTo(a['week_wins'] as int);
      });

      _logger.info('[game] getLeaderboard: ${leaderboard.length} members');
      return leaderboard;
    } catch (e) {
      _logger.severe('[game] getLeaderboard error: $e');
      return [];
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<bool> _isMember(String partyId, String userId) async {
    final row = await _db.client
        .from('party_members')
        .select('user_id')
        .eq('party_id', partyId)
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  Future<int> _partyCountForUser(String userId) async {
    final rows = await _db.client
        .from('party_members')
        .select('party_id')
        .eq('user_id', userId);
    return (rows as List).length;
  }

  static String _generateInviteCode() {
    final rng = Random.secure();
    return List.generate(
      6,
      (_) => _inviteCodeChars[rng.nextInt(_inviteCodeChars.length)],
    ).join();
  }
}
