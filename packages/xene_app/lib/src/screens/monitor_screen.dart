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
                error: (e, _) => Center(
                  child: Text(
                    'Backend offline\n$e',
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
            child: const Icon(Icons.arrow_back_ios, size: 18, color: Colors.white),
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
            style: GoogleFonts.teko(
              color: _kMuted,
              fontSize: 16,
            ),
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
    final onboarding = data['onboarding'] as Map<String, dynamic>? ?? {};
    final upkeep = data['upkeep'] as Map<String, dynamic>? ?? {};
    final perKey = (data['perKey'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final recentCalls = (data['recentCalls'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _GeminiKeySection(gemini: gemini),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _BucketCard(
                title: 'ON-BOARDING',
                subtitle: 'add-triggered',
                data: onboarding,
                color: _kTeal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BucketCard(
                title: 'UPKEEP',
                subtitle: 'scheduled batch',
                data: upkeep,
                color: _kOrange,
              ),
            ),
          ],
        ),
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
              Text(
                title,
                style: GoogleFonts.teko(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '($subtitle)',
                style: GoogleFonts.teko(color: _kMuted, fontSize: 13),
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
          Text(
            label,
            style: GoogleFonts.teko(color: _kMuted, fontSize: 14),
          ),
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
