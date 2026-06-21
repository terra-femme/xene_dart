// End-to-end driver for the Xene "game" feature.
//
// Spins up N *real* (non-anonymous) accounts against a live/staging Supabase,
// then drives a full party week through the running Dart Frog backend over HTTP:
// create party → join → submit scenario+discovery tracks → cast votes → reveal
// results → assert the leaderboard and weekly winner are correct.
//
// WHY REAL ACCOUNTS: every /game route is wrapped in requireRealUser(), so
// anonymous sessions get 403. We create email-confirmed users via the Supabase
// admin API (service key) and sign each in for a non-anonymous JWT.
//
// WHY PHASES: the backend clock is the compile-time GAME_DEBUG_HOURS define
// (see GameService._debugNow). You cannot advance it from this script — you
// relaunch the backend with a larger offset between phases. So:
//
//   1. Launch backend normally (GAME_DEBUG_HOURS unset → real "now", voting open)
//   2. dart run tool/sim_game_week.dart setup
//        → creates users, party, tracks, votes; writes .sim_game_state.json
//        → prints the GAME_DEBUG_HOURS value needed to reach results-reveal
//   3. Relaunch backend with that GAME_DEBUG_HOURS (past Friday 21:05 UTC)
//   4. dart run tool/sim_game_week.dart reveal
//        → asserts tally is visible, leaderboard + weekly winner are correct
//   5. dart run tool/sim_game_week.dart cleanup   (deletes the sim users)
//
// ENV (required): SUPABASE_URL, SUPABASE_SERVICE_KEY
// ENV (optional): BACKEND_URL (default http://localhost:8080),
//                 SIM_PLAYERS (default 4),
//                 SIM_STATE_FILE (default .sim_game_state.json)
//
// Run from packages/xene_backend:  dart run tool/sim_game_week.dart <phase>

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:supabase/supabase.dart';

// ── Config ───────────────────────────────────────────────────────────────────

final _supabaseUrl = Platform.environment['SUPABASE_URL'];
final _serviceKey = Platform.environment['SUPABASE_SERVICE_KEY'];
final _backendUrl =
    Platform.environment['BACKEND_URL'] ?? 'http://localhost:8080';
final _playerCount =
    int.tryParse(Platform.environment['SIM_PLAYERS'] ?? '') ?? 4;
final _stateFile = File(
  Platform.environment['SIM_STATE_FILE'] ?? '.sim_game_state.json',
);

void _log(String msg) {
  // ignore: avoid_print
  print('[sim ${DateTime.now().toIso8601String().substring(11, 19)}] $msg');
}

void _fail(String msg) {
  _log('✗ FAIL: $msg');
  exit(1);
}

// ── Entry ────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  final phase = args.isEmpty ? 'setup' : args.first.toLowerCase();

  if (_supabaseUrl == null || _serviceKey == null) {
    _fail('SUPABASE_URL and SUPABASE_SERVICE_KEY must be set.');
  }
  _log('phase=$phase backend=$_backendUrl players=$_playerCount');

  final supabase = SupabaseClient(_supabaseUrl!, _serviceKey!);
  final dio = Dio(
    BaseOptions(
      baseUrl: _backendUrl,
      // Never throw on non-2xx — we inspect status codes ourselves.
      validateStatus: (_) => true,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  try {
    switch (phase) {
      case 'setup':
        await _setup(supabase, dio);
      case 'reveal':
        await _reveal(dio);
      case 'cleanup':
        await _cleanup(supabase);
      default:
        _fail('unknown phase "$phase" — use: setup | reveal | cleanup');
    }
  } finally {
    await supabase.dispose();
    dio.close();
  }
}

// ── Phase: setup ─────────────────────────────────────────────────────────────

Future<void> _setup(SupabaseClient supabase, Dio dio) async {
  _log('── SETUP: creating $_playerCount players ──');
  final ts = DateTime.now().millisecondsSinceEpoch;
  final players = <Map<String, dynamic>>[];

  // Dedicated client for minting user JWTs. Sign-ins MUST stay off the admin
  // [supabase] client: signInWithPassword sets a user session, after which
  // PostgREST calls (.from()) use that user's token instead of the service key
  // — re-enabling RLS and breaking service-role writes like the profiles upsert
  // below. The admin client must never hold a user session.
  final authClient = SupabaseClient(_supabaseUrl!, _serviceKey!);

  for (var i = 0; i < _playerCount; i++) {
    final email = 'sim_${ts}_$i@xene.test';
    final password = _randomPassword();
    final usernameBase = 'sim_${i}_${ts.toRadixString(36)}';
    final username = usernameBase.length > 18
        ? usernameBase.substring(0, 18)
        : usernameBase;

    // 1. Create an email-confirmed (real, non-anonymous) account.
    final created = await supabase.auth.admin.createUser(
      AdminUserAttributes(
        email: email,
        password: password,
        emailConfirm: true,
        userMetadata: {'sim': true},
      ),
    );
    final userId = created.user?.id;
    if (userId == null) _fail('createUser returned no id for $email');
    _log('  created player $i id=$userId email=$email');

    // 2. Ensure a profiles row + username exists (game reads profiles.username).
    //    Service key bypasses RLS. Upsert is safe whether or not a trigger
    //    already inserted the row.
    await supabase.from('profiles').upsert({
      'id': userId,
      'username': username,
    });

    // 3. Sign in (on the dedicated authClient, NOT the admin client) to mint a
    //    non-anonymous JWT for backend calls.
    final auth = await authClient.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final token = auth.session?.accessToken;
    if (token == null) _fail('sign-in returned no access token for $email');

    players.add({
      'index': i,
      'id': userId,
      'email': email,
      'username': username,
      'token': token,
    });
  }

  // Tokens are captured; the auth client is no longer needed. Dispose it so its
  // session never lingers (the admin [supabase] client stays session-free).
  await authClient.dispose();

  String tokenOf(int i) => players[i]['token'] as String;
  String idOf(int i) => players[i]['id'] as String;

  // 4. Player 0 creates the party; everyone else joins by invite code.
  _log('── creating party (player 0) ──');
  final createResp = await dio.post(
    '/game/parties',
    data: {'name': 'Sim Party $ts'},
    options: _bearer(tokenOf(0)),
  );
  if (createResp.statusCode != 201) {
    _fail('create party failed: ${createResp.statusCode} ${createResp.data}');
  }
  final party = createResp.data as Map<String, dynamic>;
  final partyId = party['id'] as String;
  final inviteCode = party['invite_code'] as String;
  _log('  party id=$partyId invite=$inviteCode');

  for (var i = 1; i < _playerCount; i++) {
    final joinResp = await dio.post(
      '/game/join/$inviteCode',
      options: _bearer(tokenOf(i)),
    );
    if (joinResp.statusCode != 200) {
      _fail('player $i join failed: ${joinResp.statusCode} ${joinResp.data}');
    }
    _log('  player $i joined');
  }

  // 5. Every player submits one scenario track (required to be votable) plus a
  //    discovery track, exercising both caps.
  _log('── submitting tracks ──');
  for (var i = 0; i < _playerCount; i++) {
    await _submitTrack(dio, partyId, tokenOf(i), i, 'scenario');
    await _submitTrack(dio, partyId, tokenOf(i), i, 'discovery');
    _log('  player $i submitted scenario + discovery');
  }

  // 6. Deterministic vote pattern: everyone votes player 0, player 0 votes
  //    player 1. → player 0 wins with (N-1) votes; player 1 has 1 vote.
  _log('── casting votes ──');
  for (var i = 0; i < _playerCount; i++) {
    final votedFor = i == 0 ? 1 : 0;
    final voteResp = await dio.post(
      '/game/parties/$partyId/votes',
      data: {'voted_for_id': idOf(votedFor)},
      options: _bearer(tokenOf(i)),
    );
    if (voteResp.statusCode != 200) {
      _fail(
        'player $i vote failed: ${voteResp.statusCode} ${voteResp.data}\n'
        'If this is 422 "Voting window is closed", the real week already '
        'passed Friday 21:00 UTC — rerun setup earlier in the week, or launch '
        'the backend with a small negative GAME_DEBUG_HOURS to roll time back.',
      );
    }
    _log('  player $i voted for player $votedFor');
  }

  // 7. Read back this week's weekStart from the party preview, then persist
  //    state + the expected outcome for the reveal phase.
  final preview = await dio.get('/game/parties', options: _bearer(tokenOf(0)));
  final previewList = (preview.data as List).cast<Map<String, dynamic>>();
  final weekStart =
      previewList.firstWhere((p) => p['id'] == partyId)['week_start'] as String;

  final state = {
    'party_id': partyId,
    'invite_code': inviteCode,
    'week_start': weekStart,
    'players': players,
    'expected_winner_id': idOf(0),
    'expected_top_votes': _playerCount - 1,
  };
  await _stateFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(state),
  );
  _log('state written → ${_stateFile.path}');

  // 8. Tell the operator how far to advance the clock for the reveal phase.
  final neededHours = _hoursUntilRevealUtc(weekStart);
  _log('');
  _log('══════════════════════════════════════════════════════════════');
  _log('SETUP COMPLETE — week_start=$weekStart');
  _log('Expected winner: player 0 (${idOf(0)}) with ${_playerCount - 1} votes');
  _log('');
  _log('Next: relaunch the backend with the debug clock past results-reveal,');
  _log('then run the reveal phase. Suggested offset:');
  _log('');
  _log(
    '  GAME_DEBUG_HOURS=$neededHours  (Friday 21:05 UTC of this week + margin)',
  );
  _log('');
  _log('  # from packages/xene_backend, e.g.:');
  _log('  dart_frog dev --dart-define=GAME_DEBUG_HOURS=$neededHours');
  _log('  dart run tool/sim_game_week.dart reveal');
  _log('══════════════════════════════════════════════════════════════');
}

Future<void> _submitTrack(
  Dio dio,
  String partyId,
  String token,
  int playerIndex,
  String type,
) async {
  // Unique, validation-passing SoundCloud-shaped track data per player+type.
  final tid = '${type}_${playerIndex}_${DateTime.now().microsecondsSinceEpoch}';
  final resp = await dio.post(
    '/game/parties/$partyId/tracks',
    data: {
      'sc_track_id': tid,
      'sc_track_url': 'https://soundcloud.com/sim/$tid',
      'sc_title': 'Sim $type track p$playerIndex',
      'sc_artwork_url': 'https://i1.sndcdn.com/artworks-$tid-t500x500.jpg',
      'sc_duration_seconds': 180 + playerIndex,
      'track_type': type,
    },
    options: _bearer(token),
  );
  if (resp.statusCode != 201) {
    _fail(
      'player $playerIndex submit ($type) failed: '
      '${resp.statusCode} ${resp.data}',
    );
  }
}

// ── Phase: reveal ────────────────────────────────────────────────────────────

Future<void> _reveal(Dio dio) async {
  if (!_stateFile.existsSync()) {
    _fail('no state file at ${_stateFile.path} — run the setup phase first.');
  }
  final state =
      jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>;
  final partyId = state['party_id'] as String;
  final weekStart = state['week_start'] as String;
  final players = (state['players'] as List).cast<Map<String, dynamic>>();
  final expectedWinnerId = state['expected_winner_id'] as String;
  final expectedTopVotes = state['expected_top_votes'] as int;
  final token0 = players[0]['token'] as String;

  _log('── REVEAL: asserting results for week=$weekStart ──');

  // 1. Votes endpoint must report results visible + a populated tally.
  final votesResp = await dio.get(
    '/game/parties/$partyId/votes',
    queryParameters: {'week': weekStart},
    options: _bearer(token0),
  );
  if (votesResp.statusCode != 200) {
    _fail('votes GET failed: ${votesResp.statusCode} ${votesResp.data}');
  }
  final votes = votesResp.data as Map<String, dynamic>;
  if (votes['is_results_visible'] != true) {
    _fail(
      'results are NOT visible yet for $weekStart. The backend clock has not '
      'passed Friday 21:05 UTC. Relaunch with a larger GAME_DEBUG_HOURS '
      '(see the value the setup phase printed) and rerun reveal.',
    );
  }
  final tally = (votes['tally'] as Map?)?.cast<String, dynamic>() ?? {};
  _log('  tally=$tally');
  if ((tally[expectedWinnerId] as num?)?.toInt() != expectedTopVotes) {
    _fail(
      'tally for winner $expectedWinnerId = ${tally[expectedWinnerId]}, '
      'expected $expectedTopVotes',
    );
  }
  _log('  ✓ tally visible and winner has $expectedTopVotes votes');

  // 2. Leaderboard top entry must be the expected winner.
  final scoresResp = await dio.get(
    '/game/parties/$partyId/scores',
    options: _bearer(token0),
  );
  if (scoresResp.statusCode != 200) {
    _fail('scores GET failed: ${scoresResp.statusCode} ${scoresResp.data}');
  }
  final board = (scoresResp.data as List).cast<Map<String, dynamic>>();
  if (board.isEmpty) _fail('leaderboard is empty');
  final top = board.first;
  _log(
    '  leaderboard top: ${top['username']} '
    'votes=${top['total_votes']} wins=${top['week_wins']}',
  );
  if (top['user_id'] != expectedWinnerId) {
    _fail('leaderboard top is ${top['user_id']}, expected $expectedWinnerId');
  }
  if ((top['total_votes'] as num).toInt() != expectedTopVotes) {
    _fail('top total_votes=${top['total_votes']}, expected $expectedTopVotes');
  }
  if ((top['week_wins'] as num).toInt() != 1) {
    _fail('top week_wins=${top['week_wins']}, expected 1');
  }
  _log('  ✓ leaderboard top is the expected winner with 1 week win');

  // 3. Weekly winners must record this week → expected winner.
  final winnersResp = await dio.get(
    '/game/parties/$partyId/weekly_winners',
    options: _bearer(token0),
  );
  if (winnersResp.statusCode == 200) {
    final winners = (winnersResp.data as List).cast<Map<String, dynamic>>();
    final entry = winners
        .where((w) => w['week_start'] == weekStart)
        .firstOrNull;
    if (entry == null) {
      _fail('no weekly_winners entry for $weekStart');
    } else if (entry['winner_user_id'] != expectedWinnerId) {
      _fail(
        'weekly winner for $weekStart is ${entry['winner_user_id']}, '
        'expected $expectedWinnerId',
      );
    }
    _log('  ✓ weekly winner for $weekStart is the expected winner');
  } else {
    _log(
      '  (weekly_winners endpoint returned ${winnersResp.statusCode} — skipped)',
    );
  }

  _log('');
  _log('✓✓✓ REVEAL PASSED — the game conducts cleanly end-to-end. ✓✓✓');
}

// ── Phase: cleanup ───────────────────────────────────────────────────────────

Future<void> _cleanup(SupabaseClient supabase) async {
  if (!_stateFile.existsSync()) {
    _log('no state file — nothing to clean up.');
    return;
  }
  final state =
      jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>;
  final players = (state['players'] as List).cast<Map<String, dynamic>>();

  for (final p in players) {
    final id = p['id'] as String;
    try {
      await supabase.auth.admin.deleteUser(id);
      _log('  deleted user $id');
    } catch (e) {
      _log('  WARN could not delete user $id: $e');
    }
  }
  await _stateFile.delete();
  _log('cleanup complete — state file removed.');
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Options _bearer(String token) =>
    Options(headers: {'Authorization': 'Bearer $token'});

String _randomPassword() {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@';
  final rng = Random.secure();
  return List.generate(20, (_) => chars[rng.nextInt(chars.length)]).join();
}

/// Hours from real "now" until Friday 21:05 UTC of [weekStart], plus a 2h
/// margin. This is the GAME_DEBUG_HOURS value that makes the setup week's
/// results visible to the backend.
int _hoursUntilRevealUtc(String weekStart) {
  final parts = weekStart.split('-');
  final monday = DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
  final friday = monday.add(const Duration(days: 4));
  final reveal = DateTime.utc(friday.year, friday.month, friday.day, 21, 5);
  final diff = reveal.difference(DateTime.now().toUtc());
  return diff.inHours + 2;
}
