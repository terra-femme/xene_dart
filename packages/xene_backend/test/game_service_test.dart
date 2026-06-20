import 'package:test/test.dart';
import 'package:xene_backend/src/services/game_service.dart';

// Offline, DB-free tests for the game's "conduct" rules:
//   1. Time windows  — submission / voting / results gating across a week
//   2. Scoring        — tally, weekly winners, win counts, with multi-player ties
//
// These run under a plain `dart test` (GAME_DEBUG_HOURS unset → offset 0, so the
// service clock is real UTC now). To stay deterministic regardless of which day
// the suite runs, time-window assertions use weeks that are unambiguously in the
// past or future relative to "now" — never the live current week's mid-state.

String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The Monday `weeks` away from the current week (negative = past).
String _weekStartOffset(int weeks) {
  final parts = GameService.currentWeekStart().split('-');
  final thisMonday = DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
  return _fmt(thisMonday.add(Duration(days: 7 * weeks)));
}

/// Builds a vote row in the shape the DB returns (only the fields the pure
/// scoring helpers read).
Map<String, dynamic> _vote(String voterId, String votedForId, String week) => {
  'voter_id': voterId,
  'voted_for_id': votedForId,
  'week_start': week,
};

void main() {
  group('time windows', () {
    test('currentWeekStart() is a Monday', () {
      final parts = GameService.currentWeekStart().split('-');
      final d = DateTime.utc(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      expect(d.weekday, equals(DateTime.monday));
    });

    test('submission is OPEN for the current week, CLOSED for any other', () {
      final thisWeek = GameService.currentWeekStart();
      expect(
        GameService.isSubmissionClosed(thisWeek),
        isFalse,
        reason: 'players must be able to submit during the live week',
      );
      expect(GameService.isSubmissionClosed(_weekStartOffset(-1)), isTrue);
      expect(GameService.isSubmissionClosed(_weekStartOffset(1)), isTrue);
    });

    test('a fully-past week is closed and its results are visible', () {
      final twoWeeksAgo = _weekStartOffset(-2);
      expect(GameService.isWeekClosed(twoWeeksAgo), isTrue);
      expect(GameService.isResultsVisible(twoWeeksAgo), isTrue);
    });

    test('a future week is open and its results are hidden', () {
      final nextWeek = _weekStartOffset(2);
      expect(GameService.isWeekClosed(nextWeek), isFalse);
      expect(GameService.isResultsVisible(nextWeek), isFalse);
    });

    test('results reveal (21:05) never precedes voting close (21:00)', () {
      // For every week, results-visible implies week-closed — the 5-minute
      // gap must never invert. Probe a span of weeks around now.
      for (var w = -3; w <= 3; w++) {
        final week = _weekStartOffset(w);
        if (GameService.isResultsVisible(week)) {
          expect(
            GameService.isWeekClosed(week),
            isTrue,
            reason:
                'results were visible for $week while voting was still open',
          );
        }
      }
    });
  });

  group('tallyVotes', () {
    test('counts votes per recipient', () {
      final votes = [
        _vote('u1', 'u3', 'w1'),
        _vote('u2', 'u3', 'w1'),
        _vote('u3', 'u1', 'w1'),
        _vote('u4', 'u3', 'w1'),
      ];
      expect(GameService.tallyVotes(votes), equals({'u3': 3, 'u1': 1}));
    });

    test('empty input yields an empty tally', () {
      expect(GameService.tallyVotes([]), isEmpty);
    });
  });

  group('groupVotesByWeek', () {
    test('partitions counts per week independently', () {
      final votes = [
        _vote('u1', 'u2', 'w1'),
        _vote('u3', 'u2', 'w1'),
        _vote('u1', 'u3', 'w2'),
      ];
      final byWeek = GameService.groupVotesByWeek(votes);
      expect(byWeek['w1'], equals({'u2': 2}));
      expect(byWeek['w2'], equals({'u3': 1}));
    });
  });

  group('winsPerUserAllTied (leaderboard semantics)', () {
    test('clear winner earns one win for the week', () {
      final byWeek = GameService.groupVotesByWeek([
        _vote('a', 'c', 'w1'),
        _vote('b', 'c', 'w1'),
        _vote('c', 'a', 'w1'),
      ]);
      expect(GameService.winsPerUserAllTied(byWeek), equals({'c': 1}));
    });

    test('a tie credits EVERY tied member a win', () {
      final byWeek = GameService.groupVotesByWeek([
        _vote('a', 'b', 'w1'),
        _vote('b', 'a', 'w1'),
      ]);
      // a and b each have 1 vote → both win.
      expect(GameService.winsPerUserAllTied(byWeek), equals({'b': 1, 'a': 1}));
    });

    test('wins accumulate across multiple weeks', () {
      final byWeek = GameService.groupVotesByWeek([
        _vote('a', 'c', 'w1'),
        _vote('b', 'c', 'w1'),
        _vote('a', 'c', 'w2'),
        _vote('b', 'c', 'w2'),
      ]);
      expect(GameService.winsPerUserAllTied(byWeek), equals({'c': 2}));
    });
  });

  group('singleWinnerPerWeek (weekly-winners widget semantics)', () {
    test('picks the clear top vote-getter', () {
      final byWeek = GameService.groupVotesByWeek([
        _vote('a', 'c', 'w1'),
        _vote('b', 'c', 'w1'),
        _vote('c', 'a', 'w1'),
      ]);
      expect(GameService.singleWinnerPerWeek(byWeek), equals({'w1': 'c'}));
    });

    test('breaks a tie alphabetically by userId for stable output', () {
      final byWeek = GameService.groupVotesByWeek([
        _vote('a', 'zeb', 'w1'),
        _vote('b', 'art', 'w1'),
      ]);
      // 'art' and 'zeb' each have 1 vote → alphabetical 'art' wins.
      expect(GameService.singleWinnerPerWeek(byWeek), equals({'w1': 'art'}));
    });

    test('resolves one winner per week across weeks', () {
      final byWeek = GameService.groupVotesByWeek([
        _vote('a', 'b', 'w1'),
        _vote('c', 'b', 'w1'),
        _vote('a', 'd', 'w2'),
      ]);
      expect(
        GameService.singleWinnerPerWeek(byWeek),
        equals({'w1': 'b', 'w2': 'd'}),
      );
    });
  });

  group('end-to-end scoring (4 players, 2 weeks)', () {
    test('leaderboard totals and wins reflect every cast vote', () {
      // Week 1: p1 wins 3–1 over p2. Week 2: p2 wins 2–1 over p1 (others split).
      final votes = [
        // week 1
        _vote('p2', 'p1', 'w1'),
        _vote('p3', 'p1', 'w1'),
        _vote('p4', 'p1', 'w1'),
        _vote('p1', 'p2', 'w1'),
        // week 2
        _vote('p1', 'p2', 'w2'),
        _vote('p3', 'p2', 'w2'),
        _vote('p4', 'p1', 'w2'),
        _vote('p2', 'p3', 'w2'),
      ];

      final totals = GameService.tallyVotes(votes);
      expect(totals['p1'], equals(4)); // 3 in w1 + 1 in w2
      expect(totals['p2'], equals(3)); // 1 in w1 + 2 in w2
      expect(totals['p3'], equals(1));

      final byWeek = GameService.groupVotesByWeek(votes);
      expect(
        GameService.winsPerUserAllTied(byWeek),
        equals({'p1': 1, 'p2': 1}),
      );
      expect(
        GameService.singleWinnerPerWeek(byWeek),
        equals({'w1': 'p1', 'w2': 'p2'}),
      );
    });
  });
}
