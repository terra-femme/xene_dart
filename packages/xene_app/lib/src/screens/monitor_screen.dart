import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/monitor_provider.dart';

const _kTeal = Color(0xFF00A88F);
const _kOrange = Color(0xFFFF5500);
const _kSurface = Color(0xFF1A1A1A);
const _kCard = Color(0xFF242424);
const _kMuted = Color(0xFF888888);

String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

class MonitorScreen extends ConsumerStatefulWidget {
  const MonitorScreen({super.key});

  @override
  ConsumerState<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends ConsumerState<MonitorScreen> {
  int _countdown = 15;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    _countdown = 15;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _countdown = _countdown > 0 ? _countdown - 1 : 15;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(monitorProvider);

    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(countdown: _countdown),
            Expanded(
              child: stats.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: _kTeal),
                ),
                // An access failure is not an outage — say which one it is
                // rather than blaming the backend for a permissions problem.
                error: (e, _) => Center(
                  child: Text(
                    e is MonitorAccessDenied ? '$e' : 'Backend unreachable\n$e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _kMuted),
                  ),
                ),
                data: (data) {
                  if (data.isEmpty) {
                    return const Center(
                      child: Text(
                        'No data — backend may be offline',
                        style: TextStyle(color: _kMuted),
                      ),
                    );
                  }
                  return _Dashboard(data: data);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Capacity card ────────────────────────────────────────────────────────

class _CapacityCard extends StatelessWidget {
  const _CapacityCard({required this.capacity});
  final Map<String, dynamic> capacity;

  @override
  Widget build(BuildContext context) {
    final users = capacity['users'] as Map<String, dynamic>? ?? {};
    final storage = capacity['storage'] as Map<String, dynamic>? ?? {};

    final userCurrent = users['current'] as int? ?? 0;
    final userCap = users['cap'] as int? ?? 2000;
    final userPercent = users['percentUsed'] as double? ?? 0.0;
    final userAlert = users['alert'] as String?;

    final storageCurrent = storage['used_mb'] as double? ?? 0.0;
    final storageCap = storage['cap_mb'] as double? ?? 50.0;
    final storagePercent = storage['percentUsed'] as double? ?? 0.0;
    final storageAlert = storage['alert'] as String?;

    Color _alertColor(String? alert) {
      if (alert == 'CRITICAL') return Colors.redAccent;
      if (alert == 'WARNING') return _kOrange;
      return _kTeal;
    }

    IconData _alertIcon(String? alert) {
      if (alert == 'CRITICAL') return Icons.error_outline;
      if (alert == 'WARNING') return Icons.warning_amber_rounded;
      return Icons.check_circle_outline;
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage, color: _kTeal, size: 18),
              const SizedBox(width: 8),
              _SectionLabel('CAPACITY'),
            ],
          ),
          const SizedBox(height: 12),
          // Users
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'USERS',
                          style: GoogleFonts.teko(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          _alertIcon(userAlert),
                          size: 14,
                          color: _alertColor(userAlert),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: userPercent / 100,
                        backgroundColor: const Color(0xFF2A2A2A),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _alertColor(userAlert),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$userCurrent / $userCap (${userPercent.toStringAsFixed(1)}%)',
                      style: GoogleFonts.teko(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'STORAGE',
                          style: GoogleFonts.teko(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          _alertIcon(storageAlert),
                          size: 14,
                          color: _alertColor(storageAlert),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: storagePercent / 100,
                        backgroundColor: const Color(0xFF2A2A2A),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _alertColor(storageAlert),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${storageCurrent.toStringAsFixed(1)} / ${storageCap.toStringAsFixed(0)} MB (${storagePercent.toStringAsFixed(1)}%)',
                      style: GoogleFonts.teko(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.countdown});
  final int countdown;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: _kCard,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: const Icon(
              Icons.arrow_back_ios,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'MONITOR',
            style: GoogleFonts.teko(
              color: _kTeal,
              fontSize: 22,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          Text(
            '↺ ${countdown}s',
            style: GoogleFonts.teko(color: _kMuted, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// ── Main dashboard ────────────────────────────────────────────────────────

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final gemini = data['gemini'] as Map<String, dynamic>? ?? {};
    final capacity = data['capacity'] as Map<String, dynamic>? ?? {};
    final onboarding = data['onboarding'] as Map<String, dynamic>? ?? {};
    final upkeep = data['upkeep'] as Map<String, dynamic>? ?? {};
    final perKey =
        (data['perKey'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final recentCalls =
        (data['recentCalls'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
        [];
    final api = data['api'] as Map<String, dynamic>? ?? {};
    final apiProviders =
        (api['providers'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
        [];
    final apiRecentCalls =
        (api['recentCalls'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
        [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _GeminiKeySection(gemini: gemini),
        const SizedBox(height: 12),
        if (capacity.isNotEmpty) ...[
          _CapacityCard(capacity: capacity),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 520;
            final onboardingCard = _BucketCard(
              key: const ValueKey('monitorOnboardingBucket'),
              title: 'ON-BOARDING',
              subtitle: 'add-triggered',
              data: onboarding,
              color: _kTeal,
            );
            final upkeepCard = _BucketCard(
              key: const ValueKey('monitorUpkeepBucket'),
              title: 'UPKEEP',
              subtitle: 'scheduled batch',
              data: upkeep,
              color: _kOrange,
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  onboardingCard,
                  const SizedBox(height: 12),
                  upkeepCard,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: onboardingCard),
                const SizedBox(width: 12),
                Expanded(child: upkeepCard),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _ApiOverviewSection(api: api),
        if (apiProviders.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ApiProvidersSection(providers: apiProviders),
        ],
        if (apiRecentCalls.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RecentApiCallsSection(calls: apiRecentCalls.take(18).toList()),
        ],
        if (perKey.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PerKeySection(perKey: perKey),
        ],
        if (recentCalls.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RecentCallsSection(calls: recentCalls),
        ],
      ],
    );
  }
}

// ── Gemini key status ─────────────────────────────────────────────────────

class _GeminiKeySection extends StatelessWidget {
  const _GeminiKeySection({required this.gemini});
  final Map<String, dynamic> gemini;

  @override
  Widget build(BuildContext context) {
    final keyCount = gemini['keyCount'] as int? ?? 0;
    final currentKey = gemini['currentKeyIndex'] as int? ?? 0;
    final rotations = gemini['rotations'] as int? ?? 0;
    final hasKeys = gemini['hasKeys'] as bool? ?? false;

    return _Card(
      child: Row(
        children: [
          Icon(
            hasKeys ? Icons.vpn_key : Icons.vpn_key_off,
            color: hasKeys ? _kTeal : Colors.red,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasKeys
                  ? '$keyCount key${keyCount == 1 ? '' : 's'} · Key #$currentKey active · $rotations rotation${rotations == 1 ? '' : 's'} this session'
                  : 'No Gemini keys configured',
              style: GoogleFonts.teko(
                color: hasKeys ? Colors.white : Colors.red,
                fontSize: 16,
                letterSpacing: 0.5,
              ),
            ),
          ),
          _SectionLabel('GEMINI KEYS'),
        ],
      ),
    );
  }
}

// ── Bucket card (on-boarding / upkeep) ───────────────────────────────────

class _BucketCard extends StatelessWidget {
  const _BucketCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.data,
    required this.color,
  });
  final String title;
  final String subtitle;
  final Map<String, dynamic> data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final calls = data['calls'] as int? ?? 0;
    final inTok = data['inputTokens'] as int? ?? 0;
    final outTok = data['outputTokens'] as int? ?? 0;
    final grounded = data['groundedCalls'] as int? ?? 0;
    final cost = data['estimatedCostUsd'] as String? ?? '0.000';

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: GoogleFonts.teko(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '($subtitle)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: GoogleFonts.teko(color: _kMuted, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _StatRow('calls', '$calls'),
          _StatRow('in tokens', _fmt(inTok)),
          _StatRow('out tokens', _fmt(outTok)),
          _StatRow('grounded', '$grounded', valueColor: _kOrange),
          _StatRow('est. cost', '~\$$cost', valueColor: _kOrange),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

// ── Per-key breakdown ─────────────────────────────────────────────────────

class _ApiOverviewSection extends StatelessWidget {
  const _ApiOverviewSection({required this.api});
  final Map<String, dynamic> api;

  @override
  Widget build(BuildContext context) {
    final totals = api['totals'] as Map<String, dynamic>? ?? {};
    final calls = totals['calls'] as int? ?? 0;
    final successes = totals['successes'] as int? ?? 0;
    final failures = totals['failures'] as int? ?? 0;
    final throttles = totals['throttles'] as int? ?? 0;
    final inFlight = totals['inFlight'] as int? ?? 0;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, color: _kTeal, size: 18),
              const SizedBox(width: 8),
              _SectionLabel('API + THROTTLING'),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 540 ? 2 : 5;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: columns == 2 ? 2.6 : 1.8,
                children: [
                  _MiniMetric('calls', _fmt(calls), _kTeal),
                  _MiniMetric('ok', _fmt(successes), Colors.white),
                  _MiniMetric('fail', _fmt(failures), Colors.redAccent),
                  _MiniMetric('throttle', _fmt(throttles), _kOrange),
                  _MiniMetric('active', _fmt(inFlight), Colors.white70),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ApiProvidersSection extends StatelessWidget {
  const _ApiProvidersSection({required this.providers});
  final List<Map<String, dynamic>> providers;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('PROVIDER HEALTH'),
          const SizedBox(height: 8),
          ...providers.map((provider) => _ApiProviderRow(provider)),
        ],
      ),
    );
  }
}

class _ApiProviderRow extends StatelessWidget {
  const _ApiProviderRow(this.provider);
  final Map<String, dynamic> provider;

  @override
  Widget build(BuildContext context) {
    final name = provider['provider'] as String? ?? 'unknown';
    final calls = provider['calls'] as int? ?? 0;
    final failures = provider['failures'] as int? ?? 0;
    final throttles = provider['throttles'] as int? ?? 0;
    final inFlight = provider['inFlight'] as int? ?? 0;
    final avgLatency = provider['avgLatencyMs'] as int? ?? 0;
    final lastStatus = provider['lastStatusCode'];
    final hasRisk = throttles > 0 || failures > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: throttles > 0
              ? _kOrange.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasRisk ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            color: throttles > 0
                ? _kOrange
                : failures > 0
                ? Colors.redAccent
                : _kTeal,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              name.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.teko(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(child: _CompactStat('calls', _fmt(calls))),
          Expanded(child: _CompactStat('fail', _fmt(failures))),
          Expanded(
            child: _CompactStat(
              'limit',
              _fmt(throttles),
              valueColor: throttles > 0 ? _kOrange : Colors.white70,
            ),
          ),
          Expanded(
            child: _CompactStat('ms', avgLatency == 0 ? '-' : '$avgLatency'),
          ),
          Expanded(child: _CompactStat('open', _fmt(inFlight))),
          SizedBox(
            width: 44,
            child: Text(
              lastStatus?.toString() ?? '-',
              textAlign: TextAlign.right,
              style: GoogleFonts.teko(color: _kMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentApiCallsSection extends StatelessWidget {
  const _RecentApiCallsSection({required this.calls});
  final List<Map<String, dynamic>> calls;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('RECENT API CALLS'),
          const SizedBox(height: 8),
          ...calls.map((call) => _ApiCallRow(call)),
        ],
      ),
    );
  }
}

class _ApiCallRow extends StatelessWidget {
  const _ApiCallRow(this.call);
  final Map<String, dynamic> call;

  @override
  Widget build(BuildContext context) {
    final provider = call['provider'] as String? ?? '';
    final method = call['method'] as String? ?? '';
    final path = call['path'] as String? ?? '';
    final status = call['statusCode'];
    final ms = call['durationMs'];
    final throttled = call['throttled'] as bool? ?? false;
    final transient = call['transient'] as bool? ?? false;
    final tsRaw = call['timestamp'] as String? ?? '';

    String timeLabel = '';
    try {
      final dt = DateTime.parse(tsRaw).toLocal();
      timeLabel =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {}

    final color = throttled
        ? _kOrange
        : transient
        ? Colors.redAccent
        : Colors.white70;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              timeLabel,
              style: GoogleFonts.teko(color: _kMuted, fontSize: 13),
            ),
          ),
          SizedBox(
            width: 86,
            child: Text(
              provider.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.teko(color: color, fontSize: 13),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              method,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.teko(color: Colors.white54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              path,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.teko(color: Colors.white70, fontSize: 13),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              status?.toString() ?? '-',
              textAlign: TextAlign.right,
              style: GoogleFonts.teko(color: color, fontSize: 13),
            ),
          ),
          SizedBox(
            width: 54,
            child: Text(
              ms == null ? '-' : '${ms}ms',
              textAlign: TextAlign.right,
              style: GoogleFonts.teko(color: _kMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.teko(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.teko(color: _kMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CompactStat extends StatelessWidget {
  const _CompactStat(this.label, this.value, {this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.teko(
            color: valueColor ?? Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.teko(color: _kMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _PerKeySection extends StatelessWidget {
  const _PerKeySection({required this.perKey});
  final List<Map<String, dynamic>> perKey;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('PER-KEY BREAKDOWN'),
          const SizedBox(height: 8),
          ...perKey.map((k) {
            final idx = k['keyIndex'] as int? ?? 0;
            final calls = k['calls'] as int? ?? 0;
            final inTok = k['inputTokens'] as int? ?? 0;
            final grounded = k['groundedCalls'] as int? ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Key $idx · $calls calls · ${_fmt(inTok)} in · $grounded grounded',
                style: GoogleFonts.teko(color: Colors.white70, fontSize: 15),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

// ── Recent calls ──────────────────────────────────────────────────────────

class _RecentCallsSection extends StatelessWidget {
  const _RecentCallsSection({required this.calls});
  final List<Map<String, dynamic>> calls;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionLabel('RECENT CALLS'),
              const Spacer(),
              Text(
                'ONBOARD  SCHED',
                style: GoogleFonts.teko(color: _kMuted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...calls.map((c) => _CallRow(c)),
        ],
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow(this.call);
  final Map<String, dynamic> call;

  @override
  Widget build(BuildContext context) {
    final ctx = call['context'] as String? ?? '';
    final inTok = call['inputTokens'] as int? ?? 0;
    final grounded = call['grounded'] as bool? ?? false;
    final tsRaw = call['timestamp'] as String? ?? '';
    final isUpkeep = ctx.startsWith('press_scout.batch');

    String timeLabel = '';
    try {
      final dt = DateTime.parse(tsRaw).toLocal();
      timeLabel =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              timeLabel,
              style: GoogleFonts.teko(color: _kMuted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              ctx,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.teko(color: Colors.white70, fontSize: 14),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              _fmt(inTok),
              textAlign: TextAlign.right,
              style: GoogleFonts.teko(color: Colors.white54, fontSize: 13),
            ),
          ),
          if (grounded)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.circle, size: 7, color: _kOrange),
            )
          else
            const SizedBox(width: 11),
          // Onboard / Sched dot columns
          SizedBox(
            width: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isUpkeep)
                  const Icon(Icons.circle, size: 7, color: _kTeal)
                else
                  const SizedBox(width: 7),
                const SizedBox(width: 8),
                if (isUpkeep)
                  const Icon(Icons.circle, size: 7, color: _kOrange)
                else
                  const SizedBox(width: 7),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

// ── Shared primitives ─────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.teko(
        color: _kTeal,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value, {this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(label, style: GoogleFonts.teko(color: _kMuted, fontSize: 14)),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.teko(
              color: valueColor ?? Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
