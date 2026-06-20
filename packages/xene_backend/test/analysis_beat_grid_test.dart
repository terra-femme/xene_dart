import 'package:test/test.dart';
import 'package:xene_backend/src/services/analysis_service.dart';

// Offline, DB-free tests for `AnalysisService.estimateBeatGrid` — the BPM
// fallback that builds a beat grid from the amplitude envelope when SoundCloud
// reports no BPM (analysis_service.dart §5 of haptic_music_accessibility.md).
//
// The method is pure and static (depends only on its two arguments), so these
// run under a plain `dart test` with no backend, no DB, no network — the same
// testability convention as the pure helpers on GameService.
//
// Inputs are synthetic envelopes chosen so the result is hand-verifiable. With
// durationMs = 60000 and n = 600 samples, msPerSample = 100, which puts the
// 70–180 BPM autocorrelation window at lags 3..9 samples. A spike every 5
// samples = 500 ms = 120 BPM lands squarely inside that window (→ 'estimated');
// a spike every 20 samples sits *outside* it, so no lag aligns two peaks
// (→ the 'onset' peak-pick fallback).

const _durationMs = 60000;
const _n = 600; // msPerSample = 100

/// A flat baseline (0.1) with a sharp spike (1.0) every [period] samples.
/// The rectified first difference gives a clean onset-novelty peak at each
/// spike and zero elsewhere — a controlled input for the estimator.
List<double> _spikeEvery(int period, {int n = _n}) =>
    List<double>.generate(n, (i) => i % period == 0 ? 1.0 : 0.1);

void main() {
  group('guards — too little signal returns an empty "none" grid', () {
    test('empty samples', () {
      final r = AnalysisService.estimateBeatGrid(const [], _durationMs);
      expect(r.source, equals('none'));
      expect(r.beatGridMs, isEmpty);
    });

    test('fewer than 16 samples is rejected even with a clear pulse', () {
      // 15 samples: below the n < 16 floor, so no estimate is attempted.
      final r = AnalysisService.estimateBeatGrid(_spikeEvery(5, n: 15), 1500);
      expect(r.source, equals('none'));
      expect(r.beatGridMs, isEmpty);
    });

    test('non-positive duration is rejected', () {
      final r = AnalysisService.estimateBeatGrid(_spikeEvery(5), 0);
      expect(r.source, equals('none'));
      expect(r.beatGridMs, isEmpty);
    });

    test('a flat envelope has no onsets → none', () {
      // All samples equal → first difference is 0 everywhere → no novelty.
      final flat = List<double>.filled(_n, 0.5);
      final r = AnalysisService.estimateBeatGrid(flat, _durationMs);
      expect(r.source, equals('none'));
      expect(r.beatGridMs, isEmpty);
    });
  });

  group('estimated — a strongly periodic envelope yields a metronome grid', () {
    final r = AnalysisService.estimateBeatGrid(_spikeEvery(5), _durationMs);

    test('source is "estimated" (autocorrelation found the tempo)', () {
      expect(r.source, equals('estimated'));
    });

    test('grid is non-trivial and sorted ascending', () {
      expect(r.beatGridMs.length, greaterThanOrEqualTo(4));
      final sorted = List<int>.from(r.beatGridMs)..sort();
      expect(r.beatGridMs, equals(sorted));
    });

    test('all beats fall within [0, durationMs]', () {
      for (final ms in r.beatGridMs) {
        expect(ms, inInclusiveRange(0, _durationMs));
      }
    });

    test('beats are spaced one period (500 ms ≈ 120 BPM) apart', () {
      // period = 5 samples × 100 ms/sample = 500 ms. Each expected beat snaps
      // to its own already-present peak, so every gap is exactly 500 ms.
      for (var i = 1; i < r.beatGridMs.length; i++) {
        expect(r.beatGridMs[i] - r.beatGridMs[i - 1], equals(500));
      }
    });
  });

  group('onset — widely spaced hits fall back to peak-picking', () {
    // A spike every 20 samples (2000 ms ≈ 30 BPM) is slower than the 70–180 BPM
    // autocorrelation window can lock onto, so no lag aligns two peaks and the
    // estimator drops to the adaptive-threshold onset proxy.
    final r = AnalysisService.estimateBeatGrid(_spikeEvery(20), _durationMs);

    test('source is "onset" (no clear periodicity in the tempo window)', () {
      expect(r.source, equals('onset'));
    });

    test('it recovers the isolated hits, sorted and in range', () {
      expect(r.beatGridMs.length, greaterThanOrEqualTo(4));
      final sorted = List<int>.from(r.beatGridMs)..sort();
      expect(r.beatGridMs, equals(sorted));
      for (final ms in r.beatGridMs) {
        expect(ms, inInclusiveRange(0, _durationMs));
      }
    });

    test(
      'recovered beats are spaced ~2000 ms apart (the real hit spacing)',
      () {
        for (var i = 1; i < r.beatGridMs.length; i++) {
          expect(r.beatGridMs[i] - r.beatGridMs[i - 1], equals(2000));
        }
      },
    );
  });
}
