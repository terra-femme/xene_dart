import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_domain/xene_domain.dart';

import '../providers/artists_provider.dart';
import '../providers/discovery_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/following_provider.dart';
import '../providers/graph_provider.dart';
import '../providers/sc_search_provider.dart';
import '../providers/soundcloud_connection_provider.dart';

class ArtistsScreen extends ConsumerStatefulWidget {
  const ArtistsScreen({super.key});

  @override
  ConsumerState<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends ConsumerState<ArtistsScreen> {
  final _scSearchController = TextEditingController();
  final _followingFilterController = TextEditingController();
  final _savedFilterController = TextEditingController();

  String _followingFilter = '';
  String _savedFilter = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFollowingIfConnected();
    });
  }

  @override
  void dispose() {
    _scSearchController.dispose();
    _followingFilterController.dispose();
    _savedFilterController.dispose();
    super.dispose();
  }

  void _loadFollowingIfConnected() {
    final connection = ref.read(soundcloudConnectionProvider);
    final following = ref.read(followingProvider);
    if (connection.connected && following.status == FollowingStatus.initial) {
      ref.read(followingProvider.notifier).fetch();
    }
  }

  Future<void> _refreshFollowing() async {
    await ref.read(followingProvider.notifier).fetch(force: true);
  }

  Future<void> _disconnectSoundCloud() async {
    await ref.read(soundcloudConnectionProvider.notifier).disconnect();
    ref.read(followingProvider.notifier).reset();
  }

  Future<void> _addCandidate(Map<String, dynamic> candidate) async {
    final name = candidate['name'] as String? ?? '';
    final scUrl = candidate['soundcloud_url'] as String?;

    if (name.trim().isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(discoveryProvider.notifier)
        .autoDiscover(name, scProfileUrl: scUrl);

    if (!mounted) return;

    final discovery = ref.read(discoveryProvider);
    if (discovery.status == DiscoveryStatus.result &&
        discovery.result != null) {
      await ref
          .read(discoveryProvider.notifier)
          .saveDiscovery(discovery.result!);

      if (!mounted) return;

      final saved = ref.read(discoveryProvider);
      if (saved.status == DiscoveryStatus.saved) {
        ref.read(scSearchProvider.notifier).clear();
        _scSearchController.clear();
        await ref.read(artistsProvider.notifier).refresh();
        await _refreshDiscoveryViews();
        ref.read(discoveryProvider.notifier).reset();

        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${discovery.result!['name']} added.',
              style: GoogleFonts.archivo(fontSize: 12),
            ),
            backgroundColor: Colors.black,
          ),
        );
      } else {
        _showError(messenger, saved.error ?? 'Save failed');
      }
    } else if (discovery.status == DiscoveryStatus.error) {
      _showError(messenger, discovery.error ?? 'Discovery failed');
      ref.read(discoveryProvider.notifier).reset();
    }
  }

  Future<void> _scSearch(String query) async {
    if (query.trim().isEmpty) return;
    ref.read(discoveryProvider.notifier).reset();
    await ref.read(scSearchProvider.notifier).search(query);
  }

  void _showError(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.archivo(fontSize: 12)),
        backgroundColor: Colors.red[800],
      ),
    );
  }

  Future<void> _refreshDiscoveryViews() async {
    ref.invalidate(graphProvider);
    ref.invalidate(recentFeedProvider);
    ref.invalidate(archiveFetchProvider);
    ref.invalidate(filteredFeedProvider);
    ref.invalidate(filteredArchiveFeedProvider);
    ref.invalidate(feedArtistsProvider);
    await ref.read(feedProvider.notifier).refresh();
    Future<void>.delayed(const Duration(seconds: 3)).then((_) {
      if (!mounted) return;
      ref.read(feedProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final artistsAsync = ref.watch(artistsProvider);
    final followingState = ref.watch(followingProvider);
    final discoveryState = ref.watch(discoveryProvider);
    final scSearchState = ref.watch(scSearchProvider);
    final scState = ref.watch(soundcloudConnectionProvider);

    ref.listen(soundcloudConnectionProvider, (previous, next) {
      if (next.connected &&
          ref.read(followingProvider).status == FollowingStatus.initial) {
        ref.read(followingProvider.notifier).fetch();
      }
      if (previous?.connected == true && next.disconnected) {
        ref.read(followingProvider.notifier).reset();
      }
    });

    final savedArtists = artistsAsync.valueOrNull ?? [];
    final addedUsernames = savedArtists
        .map((artist) => artist.soundcloudUsername)
        .whereType<String>()
        .toSet();
    final isDiscovering =
        discoveryState.status == DiscoveryStatus.loading ||
        discoveryState.status == DiscoveryStatus.saving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScConnectionCard(
          scState: scState,
          onConnect: () =>
              ref.read(soundcloudConnectionProvider.notifier).connect(),
          onDisconnect: _disconnectSoundCloud,
        ),
        const Divider(color: Color(0xFFE0E0E0), height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 820;
              // Preserve the authored 460px narrow-panel target, but derive
              // the actual height from the viewport so phone/short-window
              // layouts do not clip or waste panel space. This is a content
              // guardrail only; desktop panel placement remains unchanged.
              final narrowPanelHeight = constraints.maxHeight.isFinite
                  ? (constraints.maxHeight - 24).clamp(360.0, 520.0)
                  : 460.0;
              final panels = [
                _PanelShell(
                  key: const ValueKey('artistsFollowingPanel'),
                  title: 'SOUNDCLOUD IMPORT',
                  subtitle: scState.connected
                      ? 'Imported following stays cached until disconnect'
                      : 'Connect SoundCloud to import following',
                  child: _FollowingPanel(
                    scState: scState,
                    state: followingState,
                    filterController: _followingFilterController,
                    filter: _followingFilter,
                    onFilterChanged: (value) =>
                        setState(() => _followingFilter = value),
                    onRefresh: _refreshFollowing,
                    onAddCandidate: _addCandidate,
                    isDiscovering: isDiscovering,
                    addedUsernames: addedUsernames,
                  ),
                ),
                _PanelShell(
                  key: const ValueKey('artistsSearchPanel'),
                  title: 'SOUNDCLOUD SEARCH',
                  subtitle: 'Find accounts you do not follow',
                  child: _ScSearchPanel(
                    controller: _scSearchController,
                    state: scSearchState,
                    isDiscovering: isDiscovering,
                    addedUsernames: addedUsernames,
                    onSearch: _scSearch,
                    onClear: () {
                      ref.read(scSearchProvider.notifier).clear();
                      _scSearchController.clear();
                    },
                    onAddCandidate: _addCandidate,
                  ),
                ),
                _PanelShell(
                  key: const ValueKey('artistsSavedPanel'),
                  title: 'XENE FOLLOWING',
                  subtitle: 'Saved nodes persist after SoundCloud disconnect',
                  child: _SavedArtistsPanel(
                    artistsAsync: artistsAsync,
                    filterController: _savedFilterController,
                    filter: _savedFilter,
                    onFilterChanged: (value) =>
                        setState(() => _savedFilter = value),
                    onRefresh: () =>
                        ref.read(artistsProvider.notifier).refresh(),
                    onDelete: (artist) => _confirmDelete(ref, artist),
                  ),
                ),
              ];

              if (isNarrow) {
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: panels.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      SizedBox(height: narrowPanelHeight, child: panels[index]),
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < panels.length; i++) ...[
                    Expanded(child: panels[i]),
                    if (i != panels.length - 1)
                      const VerticalDivider(color: Color(0xFFE8E8E8), width: 1),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(WidgetRef ref, Artist artist) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          'REMOVE ARTIST',
          style: GoogleFonts.teko(fontSize: 20, color: Colors.black),
        ),
        content: Text(
          'Remove ${artist.name.toUpperCase()} from Xene following? This also removes their feed items.',
          style: GoogleFonts.archivo(
            fontSize: 13,
            color: const Color(0xFF444444),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'CANCEL',
              style: GoogleFonts.teko(
                fontSize: 14,
                color: const Color(0xFF888888),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'REMOVE',
              style: GoogleFonts.teko(fontSize: 14, color: Colors.red[800]),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(artistsProvider.notifier).deleteArtist(artist.id);
      _refreshDiscoveryViews();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${artist.name} removed.',
            style: GoogleFonts.archivo(fontSize: 12),
          ),
          backgroundColor: Colors.black,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to remove artist: $e',
            style: GoogleFonts.archivo(fontSize: 12),
          ),
          backgroundColor: Colors.red[800],
        ),
      );
    }
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: GoogleFonts.teko(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: Colors.black,
              letterSpacing: 0.7,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.archivo(
              fontSize: 10,
              color: const Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _FollowingPanel extends StatelessWidget {
  const _FollowingPanel({
    required this.scState,
    required this.state,
    required this.filterController,
    required this.filter,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onAddCandidate,
    required this.isDiscovering,
    required this.addedUsernames,
  });

  final ScConnectionState scState;
  final FollowingState state;
  final TextEditingController filterController;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Map<String, dynamic> candidate) onAddCandidate;
  final bool isDiscovering;
  final Set<String> addedUsernames;

  @override
  Widget build(BuildContext context) {
    if (!scState.connected) {
      return const _EmptyPanelMessage(
        icon: Icons.cloud_off_outlined,
        title: 'SOUNDCLOUD DISCONNECTED',
        body:
            'Imported following clears on disconnect. Saved Xene following stays.',
      );
    }

    if (state.status == FollowingStatus.initial) {
      return _ActionEmptyState(
        icon: Icons.cloud_download_outlined,
        title: 'IMPORT FOLLOWING',
        body: 'Load your SoundCloud following list.',
        actionLabel: 'LOAD',
        onAction: onRefresh,
      );
    }

    if (state.status == FollowingStatus.loading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: Color(0xFFFF5500),
        ),
      );
    }

    if (state.status == FollowingStatus.error) {
      return _ActionEmptyState(
        icon: Icons.error_outline,
        title: 'IMPORT FAILED',
        body: state.error ?? 'Failed to load SoundCloud following.',
        actionLabel: 'RETRY',
        onAction: onRefresh,
      );
    }

    final candidates = state.collection.where((candidate) {
      if (filter.trim().isEmpty) return true;
      final q = filter.toLowerCase();
      final name = (candidate['name'] as String? ?? '').toLowerCase();
      final username = (candidate['soundcloud_username'] as String? ?? '')
          .toLowerCase();
      return name.contains(q) || username.contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${state.totalCount} IMPORTED',
              style: GoogleFonts.teko(
                fontSize: 13,
                color: const Color(0xFFFF5500),
                letterSpacing: 0.6,
              ),
            ),
            const Spacer(),
            _SmallTextButton(label: 'REFRESH', onTap: onRefresh),
          ],
        ),
        if (state.syncedAt != null)
          Text(
            'Synced ${state.syncedAt}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.archivo(
              fontSize: 9,
              color: const Color(0xFFAAAAAA),
            ),
          ),
        const SizedBox(height: 8),
        _FilterField(
          controller: filterController,
          hint: 'FILTER IMPORTED...',
          onChanged: onFilterChanged,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: candidates.isEmpty
              ? const _EmptyPanelMessage(
                  icon: Icons.search_off,
                  title: 'NO MATCHES',
                  body: 'Try a different filter.',
                )
              : ListView.separated(
                  itemCount: candidates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final candidate = candidates[index];
                    final username =
                        candidate['soundcloud_username'] as String?;
                    final isAdded =
                        username != null && addedUsernames.contains(username);
                    return _CandidateCard(
                      candidate: candidate,
                      isDiscovering: isDiscovering,
                      isAdded: isAdded,
                      onAdd: isAdded ? null : () => onAddCandidate(candidate),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ScSearchPanel extends StatelessWidget {
  const _ScSearchPanel({
    required this.controller,
    required this.state,
    required this.isDiscovering,
    required this.addedUsernames,
    required this.onSearch,
    required this.onClear,
    required this.onAddCandidate,
  });

  final TextEditingController controller;
  final ScSearchState state;
  final bool isDiscovering;
  final Set<String> addedUsernames;
  final Future<void> Function(String query) onSearch;
  final VoidCallback onClear;
  final Future<void> Function(Map<String, dynamic> candidate) onAddCandidate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: GoogleFonts.archivo(fontSize: 13, color: Colors.black),
                decoration: _inputDecoration(
                  hint: 'SEARCH SOUNDCLOUD...',
                  icon: Icons.search,
                ),
                onSubmitted: onSearch,
              ),
            ),
            const SizedBox(width: 8),
            _SearchButton(
              isLoading: state.status == ScSearchStatus.loading,
              onTap: () => onSearch(controller.text),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              state.query.isEmpty
                  ? 'DIRECT API LOOKUP'
                  : 'QUERY: ${state.query}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.teko(
                fontSize: 12,
                color: const Color(0xFF888888),
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            if (state.status == ScSearchStatus.results)
              _SmallTextButton(label: 'CLEAR', onTap: onClear),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildResults()),
      ],
    );
  }

  Widget _buildResults() {
    switch (state.status) {
      case ScSearchStatus.idle:
        return const _EmptyPanelMessage(
          icon: Icons.person_search_outlined,
          title: 'SEARCH ANY SOUNDCLOUD ACCOUNT',
          body: 'Use this for artists you do not follow.',
        );
      case ScSearchStatus.loading:
        return const Center(
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFFFF5500),
          ),
        );
      case ScSearchStatus.error:
        return _EmptyPanelMessage(
          icon: Icons.error_outline,
          title: 'SEARCH FAILED',
          body: state.error ?? 'SoundCloud search failed.',
        );
      case ScSearchStatus.results:
        if (state.results.isEmpty) {
          return _EmptyPanelMessage(
            icon: Icons.search_off,
            title: 'NO RESULTS',
            body: 'No SoundCloud accounts found for "${state.query}".',
          );
        }

        return ListView.separated(
          itemCount: state.results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final candidate = state.results[index];
            final username = candidate['soundcloud_username'] as String?;
            final isAdded =
                username != null && addedUsernames.contains(username);
            return _CandidateCard(
              candidate: candidate,
              isDiscovering: isDiscovering,
              isAdded: isAdded,
              onAdd: isAdded ? null : () => onAddCandidate(candidate),
            );
          },
        );
    }
  }
}

class _SavedArtistsPanel extends StatefulWidget {
  const _SavedArtistsPanel({
    required this.artistsAsync,
    required this.filterController,
    required this.filter,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onDelete,
  });

  final AsyncValue<List<Artist>> artistsAsync;
  final TextEditingController filterController;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final Future<void> Function() onRefresh;
  final ValueChanged<Artist> onDelete;

  @override
  State<_SavedArtistsPanel> createState() => _SavedArtistsPanelState();
}

class _SavedArtistsPanelState extends State<_SavedArtistsPanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _hovered ? 'REMOVE ENABLED' : 'HOVER TO MANAGE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: GoogleFonts.teko(
                    fontSize: 13,
                    color: _hovered
                        ? const Color(0xFFFF5500)
                        : const Color(0xFF888888),
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SmallTextButton(label: 'REFRESH', onTap: widget.onRefresh),
            ],
          ),
          const SizedBox(height: 8),
          _FilterField(
            controller: widget.filterController,
            hint: 'FILTER XENE FOLLOWING...',
            onChanged: widget.onFilterChanged,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.artistsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFFFF5500),
                ),
              ),
              error: (err, _) => _ActionEmptyState(
                icon: Icons.error_outline,
                title: 'FAILED TO LOAD',
                body: err.toString(),
                actionLabel: 'RETRY',
                onAction: widget.onRefresh,
              ),
              data: (artists) {
                final filtered = artists.where((artist) {
                  if (widget.filter.trim().isEmpty) return true;
                  final q = widget.filter.toLowerCase();
                  return artist.name.toLowerCase().contains(q) ||
                      (artist.soundcloudUsername ?? '').toLowerCase().contains(
                        q,
                      );
                }).toList();

                if (filtered.isEmpty) {
                  return _EmptyPanelMessage(
                    icon: Icons.people_outline,
                    title: artists.isEmpty ? 'NO XENE FOLLOWING' : 'NO MATCHES',
                    body: artists.isEmpty
                        ? 'Add artists from import or search.'
                        : 'Try a different filter.',
                  );
                }

                return RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) => _ArtistCard(
                      artist: filtered[index],
                      showRemove: _hovered,
                      onDelete: () => widget.onDelete(filtered[index]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ScConnectionCard extends StatelessWidget {
  const _ScConnectionCard({
    required this.scState,
    required this.onConnect,
    required this.onDisconnect,
  });

  final ScConnectionState scState;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final isConnected = scState.connected;
    final isPolling = scState.isPolling;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: isConnected ? const Color(0xFFF2FFF2) : const Color(0xFFFAFAFA),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFF5500),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              'SC',
              style: GoogleFonts.teko(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOUNDCLOUD',
                  style: GoogleFonts.teko(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  isPolling
                      ? 'Connecting...'
                      : isConnected
                      ? 'Connected - imported following remains until disconnect'
                      : 'Not connected',
                  style: GoogleFonts.archivo(
                    fontSize: 10,
                    color: isConnected
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFF888888),
                  ),
                ),
              ],
            ),
          ),
          if (isPolling)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Color(0xFFFF5500),
              ),
            )
          else if (isConnected)
            _OutlinedAction(label: 'DISCONNECT', onTap: onDisconnect)
          else
            _FilledAction(label: 'CONNECT', onTap: onConnect),
        ],
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({
    required this.artist,
    required this.showRemove,
    required this.onDelete,
  });

  final Artist artist;
  final bool showRemove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.name.toUpperCase(),
                  style: GoogleFonts.teko(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${artist.entityType.toUpperCase()} - ${artist.identityConfidence} - ${artist.coverageLevel}',
                  style: GoogleFonts.archivo(
                    fontSize: 10,
                    color: const Color(0xFF888888),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: showRemove ? 1 : 0,
            child: IgnorePointer(
              ignoring: !showRemove,
              child: _OutlinedAction(
                label: 'REMOVE',
                color: Colors.red[700],
                onTap: onDelete,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.onAdd,
    required this.isDiscovering,
    required this.isAdded,
  });

  final Map<String, dynamic> candidate;
  final VoidCallback? onAdd;
  final bool isDiscovering;
  final bool isAdded;

  @override
  Widget build(BuildContext context) {
    final name = candidate['name'] as String? ?? 'Unknown';
    final username = candidate['soundcloud_username'] as String? ?? '';
    final avatarUrl = candidate['avatar_url'] as String?;
    final followers = candidate['followers_count'] as int? ?? 0;
    final followersStr = followers >= 1000
        ? '${(followers / 1000).toStringAsFixed(0)}K'
        : followers.toString();

    return Container(
      height: 64,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(6),
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
                  style: GoogleFonts.teko(fontSize: 14, color: Colors.black),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  username.isEmpty
                      ? '$followersStr followers'
                      : '@$username - $followersStr followers',
                  style: GoogleFonts.archivo(
                    fontSize: 10,
                    color: const Color(0xFF888888),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: isAdded
                ? _DisabledAction(label: 'ADDED')
                : _OutlinedAction(
                    label: '+ ADD',
                    color: isDiscovering
                        ? Colors.grey.shade400
                        : const Color(0xFFFF5500),
                    onTap: isDiscovering ? null : onAdd,
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.archivo(fontSize: 13, color: Colors.black),
      decoration: _inputDecoration(hint: hint, icon: Icons.filter_list),
      onChanged: onChanged,
    );
  }
}

InputDecoration _inputDecoration({
  required String hint,
  required IconData icon,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.teko(fontSize: 14, color: const Color(0xFF888888)),
    prefixIcon: Icon(icon, color: const Color(0xFF888888), size: 18),
    filled: true,
    fillColor: const Color(0xFFF5F5F5),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide.none,
    ),
  );
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.isLoading, required this.onTap});

  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white,
                ),
              )
            : Text(
                'FIND',
                style: GoogleFonts.teko(
                  fontSize: 14,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}

class _SmallTextButton extends StatelessWidget {
  const _SmallTextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: GoogleFonts.teko(
          fontSize: 12,
          color: const Color(0xFFFF5500),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({required this.label, required this.onTap, this.color});

  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? const Color(0xFF888888);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: effectiveColor.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: GoogleFonts.teko(
            fontSize: 11,
            color: effectiveColor,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _FilledAction extends StatelessWidget {
  const _FilledAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFF5500),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: GoogleFonts.teko(
            fontSize: 11,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _DisabledAction extends StatelessWidget {
  const _DisabledAction({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.teko(fontSize: 11, color: Colors.grey.shade400),
      ),
    );
  }
}

class _ActionEmptyState extends StatelessWidget {
  const _ActionEmptyState({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFAAAAAA), size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.teko(
                fontSize: 16,
                color: const Color(0xFF888888),
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: GoogleFonts.archivo(
                fontSize: 11,
                color: const Color(0xFFAAAAAA),
              ),
            ),
            const SizedBox(height: 12),
            _OutlinedAction(
              label: actionLabel,
              color: const Color(0xFFFF5500),
              onTap: onAction,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPanelMessage extends StatelessWidget {
  const _EmptyPanelMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFAAAAAA), size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: GoogleFonts.teko(
                fontSize: 16,
                color: const Color(0xFF888888),
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.archivo(
                fontSize: 11,
                color: const Color(0xFFAAAAAA),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
