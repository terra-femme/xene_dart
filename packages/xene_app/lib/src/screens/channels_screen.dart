import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/preset_templates_provider.dart';
import '../providers/preset_sources_provider.dart';

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

// null = no filter; values match PresetSource platform fields (lowercase)
const _kPlatforms = ['soundcloud', 'bandcamp', 'youtube'];

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _platformFilter; // null = ALL
  final Set<String> _presetFilter = {}; // empty = show ALL presets

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
      () => setState(() => _query = _searchCtrl.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(presetTemplatesProvider);

    final allEnabled =
        templatesAsync.valueOrNull?.where((t) => t.enabled).toList() ?? [];
    allEnabled.sort((a, b) => a.notchIndex.compareTo(b.notchIndex));

    final visibleTemplates = _presetFilter.isEmpty
        ? allEnabled
        : allEnabled.where((t) => _presetFilter.contains(t.slug)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(child: _SearchBar(controller: _searchCtrl)),
              const SizedBox(width: 8),
              _FilterBar(
                platforms: _kPlatforms,
                selectedPlatform: _platformFilter,
                onPlatformSelect: (p) => setState(() => _platformFilter = p),
                presets: allEnabled,
                selectedPresets: _presetFilter,
                onPresetToggle: (slug) => setState(() {
                  if (_presetFilter.contains(slug)) {
                    _presetFilter.remove(slug);
                  } else {
                    _presetFilter.add(slug);
                  }
                }),
                onClearFilters: () => setState(() {
                  _platformFilter = null;
                  _presetFilter.clear();
                }),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFFE0E0E0), height: 1),
        Expanded(
          child: templatesAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF00C5A5),
              ),
            ),
            error: (e, _) => Center(
              child: Text(
                'Failed to load channels: $e',
                style: GoogleFonts.dmMono(fontSize: 12, color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
            data: (_) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 40),
              itemCount: visibleTemplates.length,
              itemBuilder: (context, i) => _PresetSection(
                template: visibleTemplates[i],
                query: _query,
                platformFilter: _platformFilter,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Search + sort bar
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: TextField(
          controller: controller,
          style: GoogleFonts.dmMono(fontSize: 12, color: Colors.black),
          decoration: InputDecoration(
            hintText: 'Search sources…',
            hintStyle: GoogleFonts.dmMono(
              fontSize: 12,
              color: const Color(0xFFAAAAAA),
            ),
            prefixIcon: const Icon(
              Icons.search,
              size: 16,
              color: Color(0xFF888888),
            ),
            suffixIcon: controller.text.isNotEmpty
                ? GestureDetector(
                    onTap: controller.clear,
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Color(0xFF888888),
                    ),
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: InputBorder.none,
            isDense: true,
          ),
        ),
    );
  }
}

// ---------------------------------------------------------------------------
// Combined filter bar — PLATFORM chips + PRESET chips
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.platforms,
    required this.selectedPlatform,
    required this.onPlatformSelect,
    required this.presets,
    required this.selectedPresets,
    required this.onPresetToggle,
    required this.onClearFilters,
  });

  final List<String> platforms;
  final String? selectedPlatform;
  final ValueChanged<String?> onPlatformSelect;
  final List<PresetTemplate> presets;
  final Set<String> selectedPresets;
  final ValueChanged<String> onPresetToggle;
  final VoidCallback onClearFilters;

  static const _platformLabels = {
    'soundcloud': 'SOUNDCLOUD',
    'bandcamp': 'BANDCAMP',
    'youtube': 'YOUTUBE',
  };

  static const _teal = Color(0xFF00C5A5);

  @override
  Widget build(BuildContext context) {
    final activeCount =
        (selectedPlatform == null ? 0 : 1) + selectedPresets.length;

    return PopupMenuButton<String>(
          tooltip: 'Filter channels',
          color: Colors.white,
          elevation: 4,
          offset: const Offset(0, 38),
          onSelected: (value) {
            if (value == 'clear') {
              onClearFilters();
              return;
            }
            if (value == 'platform:all') {
              onPlatformSelect(null);
              return;
            }
            if (value.startsWith('platform:')) {
              onPlatformSelect(value.substring('platform:'.length));
              return;
            }
            if (value.startsWith('preset:')) {
              onPresetToggle(value.substring('preset:'.length));
            }
          },
          itemBuilder: (context) => [
            _filterMenuHeader('PLATFORM'),
            CheckedPopupMenuItem<String>(
              value: 'platform:all',
              checked: selectedPlatform == null,
              height: 34,
              child: _filterMenuText('ALL PLATFORMS'),
            ),
            ...platforms.map(
              (p) => CheckedPopupMenuItem<String>(
                value: 'platform:$p',
                checked: selectedPlatform == p,
                height: 34,
                child: _filterMenuText(_platformLabels[p] ?? p.toUpperCase()),
              ),
            ),
            if (presets.isNotEmpty) const PopupMenuDivider(height: 10),
            if (presets.isNotEmpty) _filterMenuHeader('PRESETS'),
            ...presets.map(
              (t) => CheckedPopupMenuItem<String>(
                value: 'preset:${t.slug}',
                checked: selectedPresets.contains(t.slug),
                height: 34,
                child: _filterMenuText(t.name.toUpperCase()),
              ),
            ),
            if (activeCount > 0) const PopupMenuDivider(height: 10),
            if (activeCount > 0)
              PopupMenuItem<String>(
                value: 'clear',
                height: 34,
                child: _filterMenuText('CLEAR FILTERS', color: _teal),
              ),
          ],
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: activeCount > 0 ? _teal : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: activeCount > 0 ? _teal : const Color(0xFFDDDDDD),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.filter_list,
                  size: 16,
                  color: activeCount > 0 ? Colors.white : Colors.black,
                ),
                const SizedBox(width: 6),
                Text(
                  activeCount > 0 ? 'FILTER $activeCount' : 'FILTER',
                  style: GoogleFonts.dmMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: activeCount > 0
                        ? Colors.white
                        : const Color(0xFF555555),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: activeCount > 0
                      ? Colors.white
                      : const Color(0xFF777777),
                ),
              ],
            ),
          ),
    );
  }
}

PopupMenuItem<String> _filterMenuHeader(String label) {
  return PopupMenuItem<String>(
    enabled: false,
    height: 26,
    child: Text(
      label,
      style: GoogleFonts.dmMono(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: const Color(0xFFBBBBBB),
        letterSpacing: 0.8,
      ),
    ),
  );
}

Text _filterMenuText(String label, {Color color = Colors.black}) {
  return Text(
    label,
    style: GoogleFonts.dmMono(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: color,
      letterSpacing: 0.4,
    ),
    overflow: TextOverflow.ellipsis,
  );
}

// ---------------------------------------------------------------------------
// One preset section
// ---------------------------------------------------------------------------

class _PresetSection extends ConsumerWidget {
  const _PresetSection({
    required this.template,
    required this.query,
    required this.platformFilter,
  });

  final PresetTemplate template;
  final String query;
  final String? platformFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(channelSourcesProvider(template.slug));

    return sourcesAsync.when(
      // While loading show a minimal placeholder so the list doesn't jump
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Color(0xFF00C5A5),
            ),
          ),
        ),
      ),
      // Hide errored sections silently (don't break the rest of the list)
      error: (_, __) => const SizedBox.shrink(),
      data: (sources) {
        var visible = sources.where((s) => s.enabled).toList();

        // Apply platform filter
        if (platformFilter != null) {
          visible = visible.where((s) {
            switch (platformFilter) {
              case 'soundcloud':
                return s.soundcloudUrl != null || s.soundcloudUsername != null;
              case 'bandcamp':
                return s.bandcampUrl != null;
              case 'youtube':
                return s.youtubeUrl != null;
              default:
                return true;
            }
          }).toList();
          if (visible.isEmpty) return const SizedBox.shrink();
        }

        // Apply search filter — hide the whole section if nothing matches
        if (query.isNotEmpty) {
          visible = visible
              .where((s) => s.displayName.toLowerCase().contains(query))
              .toList();
          if (visible.isEmpty) return const SizedBox.shrink();
        }

        // Always sort alphabetically within each section
        visible.sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      template.name.toUpperCase(),
                      style: GoogleFonts.teko(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  if (template.description != null)
                    Expanded(
                      child: Text(
                        template.description!,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.archivo(
                          fontSize: 10,
                          color: const Color(0xFF888888),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(
              color: Color(0xFFE0E0E0),
              height: 1,
              indent: 20,
              endIndent: 20,
            ),
            const SizedBox(height: 6),

            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text(
                  'No sources yet',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: const Color(0xFF888888),
                  ),
                ),
              )
            else
              ...visible.map((s) => _SourceCard(source: s)),

            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Source card
// ---------------------------------------------------------------------------

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});
  final PresetSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              source.displayName.isNotEmpty
                  ? source.displayName[0].toUpperCase()
                  : '?',
              style: GoogleFonts.teko(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF555555),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Name + handles
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        source.displayName,
                        style: GoogleFonts.archivo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (source.manuallyVerified) ...[
                      const SizedBox(width: 4),
                      const Tooltip(
                        message: 'Verified',
                        child: Icon(
                          Icons.verified,
                          size: 13,
                          color: Color(0xFF00C5A5),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    if (source.soundcloudUsername != null)
                      _HandleChip(
                        icon: Icons.headphones,
                        label: '@${source.soundcloudUsername}',
                        color: const Color(0xFFFF5500),
                        url: source.soundcloudUrl,
                      ),
                    if (source.bandcampUrl != null)
                      _HandleChip(
                        icon: Icons.album,
                        label: 'Bandcamp',
                        color: const Color(0xFF4E9A06),
                        url: source.bandcampUrl,
                      ),
                    if (source.youtubeUrl != null)
                      _HandleChip(
                        icon: Icons.play_circle_outline,
                        label: 'YouTube',
                        color: const Color(0xFFFF4444),
                        url: source.youtubeUrl,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HandleChip extends StatelessWidget {
  const _HandleChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.url,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    return GestureDetector(
      onTap: hasUrl
          ? () =>
                launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication)
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.dmMono(
              fontSize: 9,
              color: hasUrl ? color : const Color(0xFFAAAAAA),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (hasUrl) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.open_in_new,
              size: 9,
              color: color.withValues(alpha: 0.7),
            ),
          ],
        ],
      ),
    );
  }
}
