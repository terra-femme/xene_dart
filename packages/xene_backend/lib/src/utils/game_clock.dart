// An injectable clock for the game's time-gated logic.
//
// WHY THIS EXISTS: the game opens/closes on a weekly schedule (voting closes
// Friday 21:00 UTC, results reveal 21:05 UTC). If that logic reads
// `DateTime.now()` directly it can only be tested by waiting for the real
// calendar — or by restarting the backend with a different compile-time offset.
// By treating "now" as a dependency you can swap, the boundaries become plain,
// fast, in-process unit tests (`GameClock.fixed(...)`), while production keeps
// the real wall clock (`GameClock.real()`).
//
// `GameClock.real()` still honors the `GAME_DEBUG_HOURS` compile-time define, so
// the existing manual-UI and end-to-end debug-clock workflows are unchanged.

/// A source of "now" for game time logic. Inject a [GameClock.fixed] in tests;
/// production uses [GameClock.real].
abstract class GameClock {
  /// The current UTC instant, as this clock sees it.
  DateTime now();

  /// Real wall clock (UTC), shifted by the `GAME_DEBUG_HOURS` compile-time
  /// define when set. This is the default everywhere outside tests.
  const factory GameClock.real() = _RealGameClock;

  /// A clock pinned to [fixedUtc]. Use in unit tests to assert exact boundaries.
  factory GameClock.fixed(DateTime fixedUtc) = _FixedGameClock;
}

class _RealGameClock implements GameClock {
  const _RealGameClock();

  @override
  DateTime now() {
    // Compile-time constant: zero-overhead and absent in normal production
    // builds (no --dart-define). Mirrors the previous GameService._debugNow().
    const offsetHours = int.fromEnvironment(
      'GAME_DEBUG_HOURS',
      defaultValue: 0,
    );
    if (offsetHours != 0) {
      // Preserved from the old _debugNow(): the manual debug-clock workflow
      // (docs/game-clock-how-to-use) tells operators to watch for this line.
      // ignore: avoid_print
      print('[GameClock] *** DEBUG CLOCK ACTIVE: offset=${offsetHours}h ***');
    }
    return DateTime.now().toUtc().add(const Duration(hours: offsetHours));
  }
}

class _FixedGameClock implements GameClock {
  _FixedGameClock(DateTime fixedUtc) : _now = fixedUtc.toUtc();

  final DateTime _now;

  @override
  DateTime now() => _now;
}
