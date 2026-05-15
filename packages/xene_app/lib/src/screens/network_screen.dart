import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/graph_provider.dart';

class NetworkScreen extends ConsumerWidget {
  const NetworkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(discoveryStatusProvider);
    final graphAsync = ref.watch(graphProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- LLM status banner ---
        statusAsync.when(
          loading: () => const _StatusBanner(loading: true),
          error: (_, __) => const _StatusBanner(hasProviders: false),
          data: (status) => _StatusBanner(
            hasProviders: status['has_providers'] == true,
            providers: (status['providers'] as List? ?? []).cast<String>(),
          ),
        ),

        // --- Page title ---
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                'IDENTITY GRAPH',
                style: GoogleFonts.teko(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  ref.invalidate(graphProvider);
                  ref.invalidate(discoveryStatusProvider);
                },
                child: const Icon(Icons.refresh, size: 20, color: Color(0xFF888888)),
              ),
            ],
          ),
        ),

        // --- Graph content ---
        Expanded(
          child: graphAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFF888888), size: 28),
                  const SizedBox(height: 8),
                  Text(
                    'FAILED TO LOAD GRAPH',
                    style: GoogleFonts.teko(fontSize: 15, color: const Color(0xFF888888)),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(graphProvider),
                    child: Text(
                      'RETRY',
                      style: GoogleFonts.teko(fontSize: 13, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
            data: (graph) {
              final nodes = (graph['nodes'] as List? ?? [])
                  .cast<Map<String, dynamic>>();
              final hubNodes = nodes
                  .where((n) => n['type'] == 'HUB')
                  .toList();

              if (hubNodes.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.hub_outlined,
                          size: 48, color: Color(0xFFE0E0E0)),
                      const SizedBox(height: 16),
                      Text(
                        'NO ARTISTS YET',
                        style: GoogleFonts.teko(
                            fontSize: 18, color: const Color(0xFF888888)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Add artists via the ARTISTS tab to\nbuild the identity graph.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.archivo(
                            fontSize: 12, color: const Color(0xFFAAAAAA)),
                      ),
                    ],
                  ),
                );
              }

              // Build a lookup: hubId → child nodes
              final links = (graph['links'] as List? ?? [])
                  .cast<Map<String, dynamic>>();
              final nodeById = <String, Map<String, dynamic>>{
                for (final n in nodes) n['id'] as String: n,
              };
              final childrenByHub = <String, List<Map<String, dynamic>>>{};
              for (final link in links) {
                final source = link['source'] as String? ?? '';
                final target = link['target'] as String? ?? '';
                final targetNode = nodeById[target];
                if (targetNode != null) {
                  childrenByHub.putIfAbsent(source, () => []).add(targetNode);
                }
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: hubNodes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final hub = hubNodes[index];
                  final hubId = hub['id'] as String;
                  final children = childrenByHub[hubId] ?? [];
                  return _HubCard(hub: hub, children: children);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// LLM status banner
// ---------------------------------------------------------------------------

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    this.hasProviders = false,
    this.providers = const [],
    this.loading = false,
  });

  final bool hasProviders;
  final List<String> providers;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final color = loading
        ? const Color(0xFFF5F5F5)
        : hasProviders
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFF8E1);

    final dotColor = loading
        ? const Color(0xFFBDBDBD)
        : hasProviders
            ? const Color(0xFF4CAF50)
            : const Color(0xFFFFC107);

    final label = loading
        ? 'CHECKING AI PROVIDERS...'
        : hasProviders
            ? 'AI DISCOVERY READY — ${providers.join(", ")}'
            : 'NO AI PROVIDERS — set GEMINI_API_KEY in backend';

    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.teko(
                fontSize: 12,
                color: const Color(0xFF555555),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hub card (one per saved artist)
// ---------------------------------------------------------------------------

class _HubCard extends StatelessWidget {
  const _HubCard({required this.hub, required this.children});

  final Map<String, dynamic> hub;
  final List<Map<String, dynamic>> children;

  @override
  Widget build(BuildContext context) {
    final data = hub['data'] as Map<String, dynamic>? ?? {};
    final name = hub['label'] as String? ?? 'Unknown';
    final entityType = (data['entityType'] as String? ?? 'artist').toUpperCase();
    final confidence = data['identityConfidence'] as String? ?? 'LOW';
    final coverage = data['coverageLevel'] as String? ?? 'MINIMAL';

    final dataPoints = children.where((c) => c['type'] == 'DATA_POINT').toList();
    final analyses = children.where((c) => c['type'] == 'ANALYSIS').toList();

    final confidenceColor = confidence == 'HIGH'
        ? const Color(0xFF4CAF50)
        : confidence == 'MEDIUM'
            ? const Color(0xFFFFC107)
            : const Color(0xFF888888);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.toUpperCase(),
                style: GoogleFonts.teko(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  _SmallBadge(entityType, Colors.black, Colors.white),
                  _SmallBadge(confidence, confidenceColor, Colors.white),
                  _SmallBadge(coverage, const Color(0xFFF0F0F0), const Color(0xFF666666)),
                ],
              ),
            ],
          ),
          children: [
            // DATA_POINT section
            if (dataPoints.isNotEmpty) ...[
              _SectionLabel('PLATFORM LINKS'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: dataPoints.map((n) {
                  final label = n['label'] as String? ?? '';
                  final url = (n['data'] as Map?)?['url'] as String?;
                  return GestureDetector(
                    onTap: url != null
                        ? () => launchUrl(
                              Uri.parse(url),
                              mode: LaunchMode.externalApplication,
                            )
                        : null,
                    child: _SmallBadge(
                      '↗ $label',
                      const Color(0xFFF0F0F0),
                      Colors.black,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            // ANALYSIS section
            if (analyses.isNotEmpty) ...[
              _SectionLabel('LLM ANALYSIS'),
              const SizedBox(height: 6),
              ...analyses.map((n) {
                final text = (n['data'] as Map?)?['text'] as String? ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    text,
                    style: GoogleFonts.archivo(
                      fontSize: 11,
                      color: const Color(0xFF444444),
                      height: 1.5,
                    ),
                  ),
                );
              }),
            ],

            if (dataPoints.isEmpty && analyses.isEmpty)
              Text(
                'No platform links or analysis yet.\nRun discovery to populate this card.',
                style: GoogleFonts.archivo(
                    fontSize: 11, color: const Color(0xFFAAAAAA)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.teko(
        fontSize: 11,
        color: const Color(0xFF888888),
        letterSpacing: 1,
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge(this.label, this.bg, this.fg);
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: GoogleFonts.teko(fontSize: 11, color: fg, letterSpacing: 0.3),
      ),
    );
  }
}
