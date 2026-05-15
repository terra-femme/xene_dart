import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';

import '../providers/preset_sources_provider.dart';
import '../providers/preset_templates_provider.dart';
import '../providers/sc_search_provider.dart';
import '../widgets/xene_feed_card.dart';

// Accent colour used across this screen.
const _kAccent = Color(0xFFFF5500);
const _kVerifiedColor = Color(0xFF2196F3);

class PresetPlaygroundScreen extends ConsumerStatefulWidget {
  const PresetPlaygroundScreen({super.key});

  @override
  ConsumerState<PresetPlaygroundScreen> createState() =>
      _PresetPlaygroundScreenState();
}

class _PresetPlaygroundScreenState
    extends ConsumerState<PresetPlaygroundScreen> {
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _notchController = TextEditingController();
  final _themeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sourceSearchController = TextEditingController();

  String? _selectedSlug;
  bool _isCreating = true;
  bool _enabled = true;
  bool _isDefault = false;
  bool _saving = false;
  bool _didAutoSelectInitialPreset = false;

  @override
  void initState() {
    super.initState();
    _notchController.text = '4';
    _themeController.text = '#222222';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _notchController.dispose();
    _themeController.dispose();
    _descriptionController.dispose();
    _sourceSearchController.dispose();
    super.dispose();
  }

  void _selectTemplate(PresetTemplate template) {
    setState(() {
      _selectedSlug = template.slug;
      _isCreating = false;
      _enabled = template.enabled;
      _isDefault = template.isDefault;
      _nameController.text = template.name;
      _slugController.text = template.slug;
      _notchController.text = template.notchIndex.toString();
      _themeController.text = template.themeColor;
      _descriptionController.text = template.description ?? '';
    });
    ref.read(presetSourcesProvider.notifier).load(template.slug);
  }

  void _newTemplate() {
    setState(() {
      _selectedSlug = null;
      _isCreating = true;
      _didAutoSelectInitialPreset = true;
      _enabled = true;
      _isDefault = false;
      _nameController.clear();
      _slugController.clear();
      _notchController.text = '4';
      _themeController.text = '#222222';
      _descriptionController.clear();
      _sourceSearchController.clear();
    });
    ref.read(scSearchProvider.notifier).clear();
  }

  Future<void> _searchSoundCloud() async {
    await ref
        .read(scSearchProvider.notifier)
        .search(_sourceSearchController.text);
  }

  Future<void> _addSoundCloudSource(Map<String, dynamic> candidate) async {
    final slug = _selectedSlug;
    if (slug == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(presetSourcesProvider.notifier)
          .addSoundCloudSource(slug, candidate);
      ref.read(scSearchProvider.notifier).clear();
      _sourceSearchController.clear();
      _showSnack(
        messenger,
        'Source added — fill in platform links and articles below.',
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(messenger, 'Add failed: ${_friendlyError(e)}');
    }
  }

  Future<void> _removeSource(PresetSource source) async {
    final slug = _selectedSlug;
    if (slug == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(presetSourcesProvider.notifier)
          .removeSource(slug, source.id);
      _showSnack(messenger, 'Source removed.');
    } catch (e) {
      if (!mounted) return;
      _showSnack(messenger, 'Remove failed: ${_friendlyError(e)}');
    }
  }

  Future<void> _previewPreset() async {
    final slug = _selectedSlug;
    if (slug == null) return;
    await ref.read(presetSourcesProvider.notifier).preview(slug);
  }

  Future<void> _refreshAll() async {
    final slug = _selectedSlug;
    if (slug == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result =
          await ref.read(presetSourcesProvider.notifier).refreshAll(slug);
      if (!mounted) return;
      if (result == null) {
        _showSnack(messenger, 'Refresh all failed — check backend logs.');
        return;
      }
      final artists = result['artists_refreshed'] as int? ?? 0;
      final total = result['artists_total'] as int? ?? artists;
      final byPlatform =
          (result['by_platform'] as Map<String, dynamic>?) ?? {};
      final platformSummary = byPlatform.entries.map((e) {
        final data = e.value as Map<String, dynamic>;
        return '${e.key} ${data['window_items'] ?? 0}';
      }).join(', ');
      final errors = (result['errors'] as List<dynamic>?)?.length ?? 0;
      final countLabel = artists == total ? '$artists artists' : '$artists/$total artists';
      final msg = errors > 0
          ? 'Refreshed $countLabel: $platformSummary ($errors errors)'
          : 'Refreshed $countLabel: $platformSummary';
      _showSnack(messenger, msg);
    } catch (e) {
      if (!mounted) return;
      _showSnack(messenger, 'Refresh all failed: ${_friendlyError(e)}');
    }
  }

  void _syncSlugFromName(String name) {
    if (!_isCreating) return;
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    _slugController.text = slug;
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = _nameController.text.trim();
    final slug = _slugController.text.trim();
    final notch = int.tryParse(_notchController.text.trim());
    final theme = _themeController.text.trim();

    if (name.isEmpty || slug.isEmpty || notch == null || theme.isEmpty) {
      _showSnack(messenger, 'Name, slug, notch, and color are required.');
      return;
    }

    final data = {
      'name': name,
      'slug': slug,
      'notchIndex': notch,
      'themeColor': theme,
      'isDefault': _isDefault,
      'enabled': _enabled,
      'description': _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
    };

    setState(() => _saving = true);
    try {
      final notifier = ref.read(presetTemplatesProvider.notifier);
      if (_isCreating) {
        await notifier.create(data);
      } else {
        await notifier.updateTemplate(_selectedSlug!, data);
      }
      if (!mounted) return;
      setState(() {
        _selectedSlug = slug;
        _isCreating = false;
      });
      ref.read(presetSourcesProvider.notifier).load(slug);
      _showSnack(messenger, 'Preset saved.');
    } catch (e) {
      if (!mounted) return;
      _showSnack(messenger, 'Save failed: ${_friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] != null) {
        return data['error'].toString();
      }
      return error.message ?? 'Request failed';
    }
    return error.toString();
  }

  void _showSnack(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.archivo(fontSize: 12)),
        backgroundColor: Colors.black,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(presetTemplatesProvider);
    final sourcesState = ref.watch(presetSourcesProvider);
    final searchState = ref.watch(scSearchProvider);

    return templatesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(strokeWidth: 1.5, color: _kAccent),
      ),
      error: (err, _) => _ErrorState(
        message: err.toString(),
        onRetry: () => ref.read(presetTemplatesProvider.notifier).refresh(),
      ),
      data: (templates) {
        if (_isCreating &&
            !_didAutoSelectInitialPreset &&
            _selectedSlug == null &&
            _nameController.text.isEmpty &&
            templates.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _selectedSlug != null) return;
            _didAutoSelectInitialPreset = true;
            _selectTemplate(templates.first);
          });
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 760;
            final list = _TemplateList(
              templates: templates,
              selectedSlug: _selectedSlug,
              onSelect: _selectTemplate,
              onNew: _newTemplate,
              onRefresh: () =>
                  ref.read(presetTemplatesProvider.notifier).refresh(),
            );
            final editor = _TemplateEditor(
              isCreating: _isCreating,
              saving: _saving,
              enabled: _enabled,
              isDefault: _isDefault,
              nameController: _nameController,
              slugController: _slugController,
              notchController: _notchController,
              themeController: _themeController,
              descriptionController: _descriptionController,
              onNameChanged: _syncSlugFromName,
              onEnabledChanged: (value) => setState(() => _enabled = value),
              onDefaultChanged: (value) => setState(() => _isDefault = value),
              onSave: _save,
              sourcesState: sourcesState,
              searchState: searchState,
              searchController: _sourceSearchController,
              selectedSlug: _selectedSlug,
              onSearch: _searchSoundCloud,
              onAddSource: _addSoundCloudSource,
              onRemoveSource: _removeSource,
              onPreview: _previewPreset,
              onRefreshAll: _refreshAll,
            );

            if (isNarrow) {
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  SizedBox(height: 360, child: list),
                  const SizedBox(height: 12),
                  editor,
                ],
              );
            }

            return Row(
              children: [
                SizedBox(width: 330, child: list),
                const VerticalDivider(color: Color(0xFFE8E8E8), width: 1),
                Expanded(child: editor),
              ],
            );
          },
        );
      },
    );
  }
}

class _TemplateList extends StatelessWidget {
  const _TemplateList({
    required this.templates,
    required this.selectedSlug,
    required this.onSelect,
    required this.onNew,
    required this.onRefresh,
  });

  final List<PresetTemplate> templates;
  final String? selectedSlug;
  final ValueChanged<PresetTemplate> onSelect;
  final VoidCallback onNew;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'PRESET SLOTS',
                style: GoogleFonts.teko(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                  letterSpacing: 0.7,
                ),
              ),
              const Spacer(),
              _IconAction(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                onTap: onRefresh,
              ),
              const SizedBox(width: 6),
              _IconAction(icon: Icons.add, tooltip: 'New preset', onTap: onNew),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: templates.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    itemCount: templates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final template = templates[index];
                      return _TemplateTile(
                        template: template,
                        selected: template.slug == selectedSlug,
                        onTap: () => onSelect(template),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final PresetTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(template.themeColor);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? Colors.black : const Color(0xFFE8E8E8),
            width: selected ? 1.4 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
          color: template.enabled ? Colors.white : const Color(0xFFF7F7F7),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 42,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.teko(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '${template.slug} / notch ${template.notchIndex}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.archivo(
                      fontSize: 10,
                      color: const Color(0xFF888888),
                    ),
                  ),
                ],
              ),
            ),
            if (template.isDefault)
              const Icon(
                Icons.radio_button_checked,
                size: 16,
                color: Colors.black,
              )
            else if (!template.enabled)
              const Icon(
                Icons.visibility_off,
                size: 16,
                color: Color(0xFFAAAAAA),
              ),
          ],
        ),
      ),
    );
  }
}

class _TemplateEditor extends StatelessWidget {
  const _TemplateEditor({
    required this.isCreating,
    required this.saving,
    required this.enabled,
    required this.isDefault,
    required this.nameController,
    required this.slugController,
    required this.notchController,
    required this.themeController,
    required this.descriptionController,
    required this.onNameChanged,
    required this.onEnabledChanged,
    required this.onDefaultChanged,
    required this.onSave,
    required this.sourcesState,
    required this.searchState,
    required this.searchController,
    required this.selectedSlug,
    required this.onSearch,
    required this.onAddSource,
    required this.onRemoveSource,
    required this.onPreview,
    required this.onRefreshAll,
  });

  final bool isCreating;
  final bool saving;
  final bool enabled;
  final bool isDefault;
  final TextEditingController nameController;
  final TextEditingController slugController;
  final TextEditingController notchController;
  final TextEditingController themeController;
  final TextEditingController descriptionController;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onDefaultChanged;
  final VoidCallback onSave;
  final PresetSourcesState sourcesState;
  final ScSearchState searchState;
  final TextEditingController searchController;
  final String? selectedSlug;
  final VoidCallback onSearch;
  final ValueChanged<Map<String, dynamic>> onAddSource;
  final ValueChanged<PresetSource> onRemoveSource;
  final VoidCallback onPreview;
  final VoidCallback onRefreshAll;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  isCreating ? 'NEW PRESET' : 'EDIT PRESET',
                  style: GoogleFonts.teko(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                _SaveButton(saving: saving, onTap: saving ? null : onSave),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 280,
                  child: _TextInput(
                    label: 'NAME',
                    controller: nameController,
                    onChanged: onNameChanged,
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: _TextInput(label: 'SLUG', controller: slugController),
                ),
                SizedBox(
                  width: 120,
                  child: _TextInput(
                    label: 'NOTCH',
                    controller: notchController,
                    keyboardType: TextInputType.number,
                  ),
                ),
                SizedBox(
                  width: 270,
                  child: _ColorInput(controller: themeController),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _TextInput(
              label: 'DESCRIPTION',
              controller: descriptionController,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _TogglePill(
                  label: 'ENABLED',
                  value: enabled,
                  onChanged: onEnabledChanged,
                ),
                _TogglePill(
                  label: 'DEFAULT',
                  value: isDefault,
                  onChanged: onDefaultChanged,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SourceWorkbench(
              enabled: selectedSlug != null && !isCreating,
              sourcesState: sourcesState,
              searchState: searchState,
              searchController: searchController,
              onSearch: onSearch,
              onAddSource: onAddSource,
              onRemoveSource: onRemoveSource,
              onPreview: onPreview,
              onRefreshAll: onRefreshAll,
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceWorkbench extends StatelessWidget {
  const _SourceWorkbench({
    required this.enabled,
    required this.sourcesState,
    required this.searchState,
    required this.searchController,
    required this.onSearch,
    required this.onAddSource,
    required this.onRemoveSource,
    required this.onPreview,
    required this.onRefreshAll,
  });

  final bool enabled;
  final PresetSourcesState sourcesState;
  final ScSearchState searchState;
  final TextEditingController searchController;
  final VoidCallback onSearch;
  final ValueChanged<Map<String, dynamic>> onAddSource;
  final ValueChanged<PresetSource> onRemoveSource;
  final VoidCallback onPreview;
  final VoidCallback onRefreshAll;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const _MutedPanelMessage(
        title: 'SAVE OR SELECT A PRESET',
        body: 'Sources and preview unlock once a preset slot exists.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'SOURCES',
              style: GoogleFonts.teko(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                letterSpacing: 0.7,
              ),
            ),
            const Spacer(),
            _SmallActionButton(
              label: sourcesState.loadingRefreshAll ? 'REFRESHING...' : 'REFRESH ALL',
              icon: sourcesState.loadingRefreshAll
                  ? Icons.hourglass_top_outlined
                  : Icons.refresh,
              onTap: sourcesState.loadingRefreshAll ||
                      sourcesState.sources.isEmpty
                  ? null
                  : onRefreshAll,
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 720;
            final assigned = _AssignedSourcesPanel(
              state: sourcesState,
              onRemove: onRemoveSource,
            );
            final search = _SoundCloudSourceSearchPanel(
              state: searchState,
              controller: searchController,
              onSearch: onSearch,
              onAdd: onAddSource,
            );
            if (isNarrow) {
              return Column(
                children: [
                  SizedBox(height: 280, child: assigned),
                  const SizedBox(height: 12),
                  SizedBox(height: 340, child: search),
                ],
              );
            }
            return SizedBox(
              height: 340,
              child: Row(
                children: [
                  Expanded(child: assigned),
                  const SizedBox(width: 12),
                  Expanded(child: search),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        _PresetPreviewPanel(state: sourcesState, onPreview: onPreview),
      ],
    );
  }
}

class _AssignedSourcesPanel extends StatefulWidget {
  const _AssignedSourcesPanel({required this.state, required this.onRemove});

  final PresetSourcesState state;
  final ValueChanged<PresetSource> onRemove;

  @override
  State<_AssignedSourcesPanel> createState() => _AssignedSourcesPanelState();
}

class _AssignedSourcesPanelState extends State<_AssignedSourcesPanel> {
  String? _expandedSourceId;

  @override
  void didUpdateWidget(_AssignedSourcesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final slugChanged = widget.state.slug != oldWidget.state.slug;
    if (slugChanged) {
      // Switched presets — collapse any open card.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _expandedSourceId = null);
      });
    } else if (widget.state.sources.length > oldWidget.state.sources.length &&
        widget.state.sources.isNotEmpty) {
      // A source was just added — auto-expand its card.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _expandedSourceId = widget.state.sources.last.id);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final slug = widget.state.slug ?? '';
    return _PanelBox(
      title: 'ASSIGNED',
      child: widget.state.loadingSources
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: _kAccent,
              ),
            )
          : widget.state.sources.isEmpty
          ? const _MutedPanelMessage(
              title: 'NO SOURCES YET',
              body: 'Search SoundCloud and add profiles to fill this preset.',
            )
          : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: widget.state.sources.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final source = widget.state.sources[index];
                return _SourceRow(
                  key: ValueKey(source.id),
                  source: source,
                  slug: slug,
                  isExpanded: _expandedSourceId == source.id,
                  onExpand: () => setState(() => _expandedSourceId = source.id),
                  onCollapse: () => setState(() => _expandedSourceId = null),
                  onRemove: () => widget.onRemove(source),
                );
              },
            ),
    );
  }
}

class _SoundCloudSourceSearchPanel extends StatelessWidget {
  const _SoundCloudSourceSearchPanel({
    required this.state,
    required this.controller,
    required this.onSearch,
    required this.onAdd,
  });

  final ScSearchState state;
  final TextEditingController controller;
  final VoidCallback onSearch;
  final ValueChanged<Map<String, dynamic>> onAdd;

  @override
  Widget build(BuildContext context) {
    return _PanelBox(
      title: 'SOUNDCLOUD SEARCH',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onSubmitted: (_) => onSearch(),
                  style: GoogleFonts.archivo(fontSize: 13, color: Colors.black),
                  decoration: _inputDecoration('SEARCH PROFILE'),
                ),
              ),
              const SizedBox(width: 8),
              _SmallActionButton(
                label: state.status == ScSearchStatus.loading ? '...' : 'FIND',
                icon: Icons.search,
                onTap: state.status == ScSearchStatus.loading ? null : onSearch,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    switch (state.status) {
      case ScSearchStatus.idle:
        return const _MutedPanelMessage(
          title: 'READY',
          body: 'Search for a SoundCloud profile to add as a preset source.',
        );
      case ScSearchStatus.loading:
        return const Center(
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFFFF5500),
          ),
        );
      case ScSearchStatus.error:
        return _MutedPanelMessage(
          title: 'SEARCH FAILED',
          body: state.error ?? 'Could not search SoundCloud.',
        );
      case ScSearchStatus.results:
        if (state.results.isEmpty) {
          return const _MutedPanelMessage(
            title: 'NO RESULTS',
            body: 'Try a different query.',
          );
        }
        return ListView.separated(
          itemCount: state.results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final candidate = state.results[index];
            return _SearchResultRow(
              candidate: candidate,
              onAdd: () => onAdd(candidate),
            );
          },
        );
    }
  }
}

class _PresetPreviewPanel extends StatelessWidget {
  const _PresetPreviewPanel({required this.state, required this.onPreview});

  final PresetSourcesState state;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 420,
      child: _PanelBox(
        title: 'PREVIEW',
        trailing: _SmallActionButton(
          label: state.loadingPreview ? 'LOADING' : 'RUN PREVIEW',
          icon: Icons.visibility_outlined,
          onTap: state.loadingPreview ? null : onPreview,
        ),
        child: state.loadingPreview
            ? const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFFFF5500),
                ),
              )
            : state.previewItems.isEmpty
            ? const _MutedPanelMessage(
                title: 'NO PREVIEW YET',
                body: 'Run preview after adding sources.',
              )
            : ListView.separated(
                itemCount: state.previewItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) =>
                    XeneFeedCard(item: state.previewItems[index]),
              ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.label,
    required this.controller,
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: GoogleFonts.archivo(fontSize: 13, color: Colors.black),
      decoration: _inputDecoration(label),
    );
  }
}

class _ColorInput extends StatelessWidget {
  const _ColorInput({required this.controller});

  final TextEditingController controller;

  static const _swatches = [
    '#FF5500',
    '#FFD400',
    '#00A88F',
    '#00B7FF',
    '#4F46E5',
    '#8A2BE2',
    '#E044A7',
    '#FF3B5C',
    '#42A5F5',
    '#4CAF50',
    '#C9A96E',
    '#222222',
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final selected = value.text.trim().toUpperCase();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              style: GoogleFonts.archivo(fontSize: 13, color: Colors.black),
              decoration: _inputDecoration('COLOR').copyWith(
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _parseColor(value.text),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final hex in _swatches)
                  Tooltip(
                    message: hex,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => controller.text = hex,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _parseColor(hex),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: selected == hex
                                ? Colors.black
                                : const Color(0xFFE0E0E0),
                            width: selected == hex ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TogglePill extends StatelessWidget {
  const _TogglePill({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.teko(
          fontSize: 13,
          color: value ? Colors.white : const Color(0xFF555555),
          letterSpacing: 0.5,
        ),
      ),
      selected: value,
      selectedColor: Colors.black,
      backgroundColor: const Color(0xFFF5F5F5),
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      onSelected: onChanged,
    );
  }
}

class _PanelBox extends StatelessWidget {
  const _PanelBox({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.teko(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 6),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SourceRow extends ConsumerStatefulWidget {
  const _SourceRow({
    super.key,
    required this.source,
    required this.slug,
    required this.isExpanded,
    required this.onExpand,
    required this.onCollapse,
    required this.onRemove,
  });

  final PresetSource source;
  final String slug;
  final bool isExpanded;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final VoidCallback onRemove;

  @override
  ConsumerState<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends ConsumerState<_SourceRow> {
  final _bandcampController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _articleTitleController = TextEditingController();
  final _articleUrlController = TextEditingController();
  final _articleSourceController = TextEditingController();

  bool _savingLinks = false;
  bool _addingArticle = false;
  bool _refreshingFeed = false;

  @override
  void initState() {
    super.initState();
    _bandcampController.text = widget.source.bandcampUrl ?? '';
    _youtubeController.text = widget.source.youtubeUrl ?? '';
  }

  @override
  void didUpdateWidget(_SourceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.id != widget.source.id) {
      _bandcampController.text = widget.source.bandcampUrl ?? '';
      _youtubeController.text = widget.source.youtubeUrl ?? '';
    } else {
      // Keep controllers in sync after a successful PATCH reloads the source.
      if (widget.source.bandcampUrl != null &&
          _bandcampController.text.isEmpty) {
        _bandcampController.text = widget.source.bandcampUrl!;
      }
      if (widget.source.youtubeUrl != null && _youtubeController.text.isEmpty) {
        _youtubeController.text = widget.source.youtubeUrl!;
      }
    }
  }

  @override
  void dispose() {
    _bandcampController.dispose();
    _youtubeController.dispose();
    _articleTitleController.dispose();
    _articleUrlController.dispose();
    _articleSourceController.dispose();
    super.dispose();
  }

  Future<void> _saveLinks() async {
    final bc = _bandcampController.text.trim();
    final yt = _youtubeController.text.trim();
    if (bc.isEmpty && yt.isEmpty) return;
    setState(() => _savingLinks = true);
    try {
      await ref
          .read(presetSourcesProvider.notifier)
          .patchSource(
            widget.slug,
            widget.source.id,
            bandcampUrl: bc.isEmpty ? null : bc,
            youtubeUrl: yt.isEmpty ? null : yt,
          );
      if (mounted) _snack('Links saved. Feed is warming up in the background.');
    } catch (e) {
      if (mounted) _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _savingLinks = false);
    }
  }

  Future<void> _addArticle() async {
    final title = _articleTitleController.text.trim();
    final url = _articleUrlController.text.trim();
    if (title.isEmpty || url.isEmpty) return;
    setState(() => _addingArticle = true);
    try {
      await ref
          .read(presetSourcesProvider.notifier)
          .addArticle(
            widget.slug,
            widget.source.id,
            title: title,
            url: url,
            source: _articleSourceController.text.trim().isEmpty
                ? null
                : _articleSourceController.text.trim(),
          );
      _articleTitleController.clear();
      _articleUrlController.clear();
      _articleSourceController.clear();
      if (mounted) _snack('Article saved.');
    } catch (e) {
      if (mounted) _snack('Add failed: $e');
    } finally {
      if (mounted) setState(() => _addingArticle = false);
    }
  }

  Future<void> _refreshFeed() async {
    setState(() => _refreshingFeed = true);
    try {
      final result = await ref
          .read(presetSourcesProvider.notifier)
          .refreshSource(widget.slug, widget.source.id);
      final platforms = (result?['platforms'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) {
            final platform = row['platform']?.toString() ?? 'platform';
            final count = row['window_items'] ?? row['items_fetched'] ?? 0;
            return '$platform $count';
          })
          .join(', ');
      if (mounted) {
        _snack(
          platforms.isEmpty ? 'Feed refreshed.' : 'Feed refreshed: $platforms',
        );
      }
    } catch (e) {
      if (mounted) _snack('Refresh failed: $e');
    } finally {
      if (mounted) setState(() => _refreshingFeed = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.archivo(fontSize: 12)),
        backgroundColor: Colors.black,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(5),
        border: widget.isExpanded
            ? Border.all(color: const Color(0xFFE0E0E0))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header row (always visible) ──────────────────────
          InkWell(
            onTap: widget.isExpanded ? widget.onCollapse : widget.onExpand,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              child: Row(
                children: [
                  const Icon(Icons.cloud_outlined, size: 17, color: _kAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                source.displayName.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.teko(
                                  fontSize: 15,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            if (source.manuallyVerified) ...[
                              const SizedBox(width: 4),
                              const Tooltip(
                                message: 'Dev-verified artist',
                                child: Icon(
                                  Icons.verified,
                                  size: 13,
                                  color: _kVerifiedColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          source.soundcloudUsername == null
                              ? 'soundcloud'
                              : '@${source.soundcloudUsername}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.archivo(
                            fontSize: 10,
                            color: const Color(0xFF888888),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    widget.isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: const Color(0xFF888888),
                  ),
                  IconButton(
                    tooltip: 'Refresh feed',
                    icon: _refreshingFeed
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: _kAccent,
                            ),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    color: const Color(0xFF888888),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: _refreshingFeed ? null : _refreshFeed,
                  ),
                  IconButton(
                    tooltip: 'Remove source',
                    icon: const Icon(Icons.close, size: 16),
                    color: const Color(0xFF888888),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: widget.onRemove,
                  ),
                ],
              ),
            ),
          ),
          // ── Inline profile card (expanded only) ─────────────
          if (widget.isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1, color: Color(0xFFE8E8E8)),
                  const SizedBox(height: 10),
                  // Platform links section
                  Text(
                    'PLATFORM LINKS',
                    style: GoogleFonts.teko(
                      fontSize: 12,
                      color: const Color(0xFF888888),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _bandcampController,
                    style: GoogleFonts.archivo(
                      fontSize: 12,
                      color: Colors.black,
                    ),
                    decoration: _inputDecoration('BANDCAMP URL'),
                  ),
                  const SizedBox(height: 5),
                  TextField(
                    controller: _youtubeController,
                    style: GoogleFonts.archivo(
                      fontSize: 12,
                      color: Colors.black,
                    ),
                    decoration: _inputDecoration('YOUTUBE URL'),
                  ),
                  const SizedBox(height: 7),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _SmallActionButton(
                      label: _savingLinks ? '...' : 'SAVE LINKS',
                      icon: Icons.save_outlined,
                      onTap: _savingLinks ? null : _saveLinks,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Articles section
                  Text(
                    'ARTICLES',
                    style: GoogleFonts.teko(
                      fontSize: 12,
                      color: const Color(0xFF888888),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _articleTitleController,
                    style: GoogleFonts.archivo(
                      fontSize: 12,
                      color: Colors.black,
                    ),
                    decoration: _inputDecoration('TITLE'),
                  ),
                  const SizedBox(height: 5),
                  TextField(
                    controller: _articleUrlController,
                    style: GoogleFonts.archivo(
                      fontSize: 12,
                      color: Colors.black,
                    ),
                    decoration: _inputDecoration('URL'),
                  ),
                  const SizedBox(height: 5),
                  TextField(
                    controller: _articleSourceController,
                    style: GoogleFonts.archivo(
                      fontSize: 12,
                      color: Colors.black,
                    ),
                    decoration: _inputDecoration(
                      'SOURCE  (e.g. Resident Advisor)',
                    ),
                  ),
                  const SizedBox(height: 7),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _SmallActionButton(
                      label: _addingArticle ? '...' : 'ADD ARTICLE',
                      icon: Icons.add,
                      onTap: _addingArticle ? null : _addArticle,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({required this.candidate, required this.onAdd});

  final Map<String, dynamic> candidate;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final name = candidate['name'] as String? ?? 'Unknown';
    final username = candidate['soundcloud_username'] as String? ?? '';
    final avatarUrl = candidate['avatar_url'] as String?;
    final followers = candidate['followers_count'] as int? ?? 0;
    final followersStr = followers >= 1000000
        ? '${(followers / 1000000).toStringAsFixed(1)}M'
        : followers >= 1000
        ? '${(followers / 1000).toStringAsFixed(0)}K'
        : followers.toString();

    return Container(
      height: 64,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(5),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(7),
            child: CircleAvatar(
              radius: 21,
              backgroundColor: const Color(0xFFF0F0F0),
              backgroundImage: avatarUrl != null
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: GoogleFonts.teko(
                        fontSize: 16,
                        color: const Color(0xFF888888),
                      ),
                    )
                  : null,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.teko(fontSize: 14, color: Colors.black),
                ),
                Text(
                  username.isEmpty
                      ? '$followersStr followers'
                      : '@$username - $followersStr followers',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.archivo(
                    fontSize: 10,
                    color: const Color(0xFF888888),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _SmallActionButton(
              label: 'ADD',
              icon: Icons.add,
              onTap: onAdd,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: onTap == null ? const Color(0xFFAAAAAA) : Colors.black,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.teko(
                fontSize: 13,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MutedPanelMessage extends StatelessWidget {
  const _MutedPanelMessage({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.teko(
                fontSize: 15,
                color: const Color(0xFF888888),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: GoogleFonts.archivo(
                fontSize: 10,
                color: const Color(0xFFAAAAAA),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 16, color: Colors.black),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saving, required this.onTap});

  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: onTap == null ? const Color(0xFFAAAAAA) : Colors.black,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: saving
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.save_outlined,
                    size: 15,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'SAVE',
                    style: GoogleFonts.teko(
                      fontSize: 14,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFF5500), size: 28),
            const SizedBox(height: 8),
            Text(
              'LOAD FAILED',
              style: GoogleFonts.teko(fontSize: 18, color: Colors.black),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.archivo(
                fontSize: 11,
                color: const Color(0xFF888888),
              ),
            ),
            const SizedBox(height: 12),
            _RetryButton(onTap: onRetry),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'NO PRESETS',
        style: GoogleFonts.teko(fontSize: 18, color: const Color(0xFF888888)),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: _kAccent),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          'RETRY',
          style: GoogleFonts.teko(
            fontSize: 13,
            color: _kAccent,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.teko(fontSize: 14, color: const Color(0xFF888888)),
    filled: true,
    fillColor: const Color(0xFFF5F5F5),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide.none,
    ),
  );
}

Color _parseColor(String value) {
  final hex = value.replaceFirst('#', '');
  final parsed = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return Color(parsed ?? 0xFF222222);
}
