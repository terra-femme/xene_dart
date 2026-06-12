class TrackAnalysis {
  const TrackAnalysis({
    required this.trackId,
    required this.platform,
    this.bpm,
    required this.beatGridMs,
    required this.amplitudeSamples,
    required this.energyEventsMs,
    required this.analyzedAt,
  });

  final String trackId;
  final String platform;
  final int? bpm;
  final List<int> beatGridMs;
  final List<double> amplitudeSamples;
  final List<int> energyEventsMs;
  final DateTime analyzedAt;

  factory TrackAnalysis.fromJson(Map<String, dynamic> j) => TrackAnalysis(
    trackId: j['track_id'] as String,
    platform: j['platform'] as String,
    bpm: (j['bpm'] as num?)?.toInt(),
    beatGridMs: (j['beat_grid_ms'] as List? ?? [])
        .map((e) => (e as num).toInt())
        .toList(),
    amplitudeSamples: (j['amplitude_samples'] as List? ?? [])
        .map((e) => (e as num).toDouble())
        .toList(),
    energyEventsMs: (j['energy_events_ms'] as List? ?? [])
        .map((e) => (e as num).toInt())
        .toList(),
    analyzedAt: DateTime.parse(j['analyzed_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'track_id': trackId,
    'platform': platform,
    if (bpm != null) 'bpm': bpm,
    'beat_grid_ms': beatGridMs,
    'amplitude_samples': amplitudeSamples,
    'energy_events_ms': energyEventsMs,
    'analyzed_at': analyzedAt.toUtc().toIso8601String(),
  };
}
