import 'package:test/test.dart';
import 'package:xene_backend/src/services/game_service.dart';
import 'package:xene_backend/src/utils/game_clock.dart';

// Exact time-boundary tests enabled by clock injection. Unlike
// game_service_test.dart (which asserts against "unambiguously past/future"
// weeks because it runs on the real clock), these pin "now" to a specific UTC
// instant and assert the knife-edge transitions precisely — no DB, no backend,
// no GAME_DEBUG_HOURS, no flakiness.
//
// Reference week used throughout: Monday 2026-06-15.
//   week_start (Mon) = 2026-06-15
//   voting closes    = Friday 2026-06-19 21:00 UTC
//   results reveal   = Friday 2026-06-19 21:05 UTC
const _week = '2026-06-15';

/// A clock pinned to a specific UTC instant.
GameClock at(DateTime utc) => GameClock.fixed(utc);

void main() {
  group('currentWeekStart', () {
    test('mid-week (Wed) resolves to that week\'s Monday', () {
      final clock = at(DateTime.utc(2026, 6, 17, 12)); // Wed 2026-06-17 noon
      expect(GameService.currentWeekStart(clock), equals('2026-06-15'));
    });

    test('Monday 00:00 is already in its own week', () {
      final clock = at(DateTime.utc(2026, 6, 15, 0, 0));
      expect(GameService.currentWeekStart(clock), equals('2026-06-15'));
    });

    test('Sunday 23:59 still belongs to the week that started Monday', () {
      final clock = at(DateTime.utc(2026, 6, 21, 23, 59)); // Sun of that week
      expect(GameService.currentWeekStart(clock), equals('2026-06-15'));
    });

    test('the next Monday rolls over to a new week', () {
      final clock = at(DateTime.utc(2026, 6, 22, 0, 0)); // Mon 2026-06-22
      expect(GameService.currentWeekStart(clock), equals('2026-06-22'));
    });
  });

  group('isWeekClosed — voting closes Friday 21:00 UTC', () {
    test('OPEN at Friday 20:59 (one minute before close)', () {
      final clock = at(DateTime.utc(2026, 6, 19, 20, 59));
      expect(GameService.isWeekClosed(_week, clock), isFalse);
    });

    test('OPEN exactly at 21:00 (boundary is "after", not "at")', () {
      final clock = at(DateTime.utc(2026, 6, 19, 21, 0, 0));
      expect(GameService.isWeekClosed(_week, clock), isFalse);
    });

    test('CLOSED one second past 21:00', () {
      final clock = at(DateTime.utc(2026, 6, 19, 21, 0, 1));
      expect(GameService.isWeekClosed(_week, clock), isTrue);
    });
  });

  group('isResultsVisible — results reveal Friday 21:05 UTC', () {
    test('HIDDEN at 21:00 (voting just closed, 5-min gap not elapsed)', () {
      final clock = at(DateTime.utc(2026, 6, 19, 21, 0, 1));
      expect(GameService.isResultsVisible(_week, clock), isFalse);
    });

    test('HIDDEN exactly at 21:05 (boundary is "after")', () {
      final clock = at(DateTime.utc(2026, 6, 19, 21, 5, 0));
      expect(GameService.isResultsVisible(_week, clock), isFalse);
    });

    test('VISIBLE one second past 21:05', () {
      final clock = at(DateTime.utc(2026, 6, 19, 21, 5, 1));
      expect(GameService.isResultsVisible(_week, clock), isTrue);
    });
  });

  group('the 5-minute reveal gap is real', () {
    test('between 21:01 and 21:05: voting CLOSED but results still HIDDEN', () {
      final clock = at(DateTime.utc(2026, 6, 19, 21, 3));
      expect(GameService.isWeekClosed(_week, clock), isTrue);
      expect(GameService.isResultsVisible(_week, clock), isFalse);
    });
  });

  group('isSubmissionClosed — flips exactly at the week boundary', () {
    test('OPEN mid-week (this is the current week)', () {
      final clock = at(DateTime.utc(2026, 6, 17, 12));
      expect(GameService.isSubmissionClosed(_week, clock), isFalse);
    });

    test('OPEN even on Friday night after voting closes (same week)', () {
      // Submission stays open the whole week; only voting/results are gated.
      final clock = at(DateTime.utc(2026, 6, 19, 22, 0));
      expect(GameService.isSubmissionClosed(_week, clock), isFalse);
    });

    test('CLOSED once the next week begins', () {
      final clock = at(DateTime.utc(2026, 6, 22, 0, 0)); // next Monday
      expect(GameService.isSubmissionClosed(_week, clock), isTrue);
    });
  });
}
