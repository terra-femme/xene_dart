import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logging/logging.dart';

import '../providers/dio_provider.dart';
import '../theme/xene_theme.dart';

final _logger = Logger('sc_track_search');

/// Reusable SoundCloud catalog search for the dev AV tabs.
///
/// Renders a search box + tappable results (artwork, title, artist · duration).
/// Calls [onSelected] with the chosen track's numeric id, a `artist — title`
/// label, and its artwork url. Replaces pasting numeric track IDs.
///
/// Backed by `GET /soundcloud/track_search?q=` (real-account gated — anonymous
/// sessions get a 403, surfaced inline).
class ScTrackSearch extends ConsumerStatefulWidget {
  const ScTrackSearch({super.key, required this.onSelected, this.hintText});

  final void Function(String trackId, String label, String? artworkUrl)
  onSelected;
  final String? hintText;

  @override
  ConsumerState<ScTrackSearch> createState() => _ScTrackSearchState();
}

class _ScTrackSearchState extends ConsumerState<ScTrackSearch> {
  final _controller = TextEditingController();
  bool _searching = false;
  List<Map<String, dynamic>> _results = [];
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() => _error = 'Enter a search, e.g. "galimatias - lonely".');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });
    final dio = ref.read(authenticatedDioProvider);
    try {
      _logger.info('[scSearch] GET /soundcloud/track_search?q="$q"');
      final resp = await dio.get<Map<String, dynamic>>(
        '/soundcloud/track_search',
        queryParameters: {'q': q},
      );
      final collection = (resp.data?['collection'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      _logger.info('[scSearch] "$q" -> ${collection.length} results');
      setState(() {
        _results = collection;
        if (collection.isEmpty) _error = 'No SoundCloud tracks matched "$q".';
      });
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      _logger.warning('[scSearch] failed status=$code: ${e.message}');
      setState(() {
        _error = switch (code) {
          403 =>
            'Sign in with a REAL account (not the anonymous session) to search.',
          401 => 'Unauthorized — sign in first.',
          400 => 'Empty query.',
          _ => 'Search error (status=$code).',
        };
      });
    } catch (e) {
      _logger.warning('[scSearch] error: $e');
      setState(() => _error = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: GoogleFonts.dmMono(fontSize: 13),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText:
                      widget.hintText ??
                      'Search SoundCloud, e.g. galimatias - lonely',
                  hintStyle: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: XeneTheme.muted,
                  ),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _searching ? null : _search,
                child: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('SEARCH', style: GoogleFonts.teko(letterSpacing: 1)),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: GoogleFonts.dmMono(
              fontSize: 11,
              height: 1.5,
              color: XeneTheme.orange,
            ),
          ),
        ],
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._results.map((t) {
            final id = t['id'] as String? ?? '';
            final title = t['title'] as String? ?? 'Unknown';
            final user = t['username'] as String? ?? 'Unknown';
            final art = t['artwork_url'] as String?;
            final dur = t['duration_seconds'] as int? ?? 0;
            return _ScResultRow(
              title: title,
              username: user,
              artworkUrl: art,
              durationSeconds: dur,
              onTap: id.isEmpty
                  ? null
                  : () => widget.onSelected(id, '$user — $title', art),
            );
          }),
        ],
      ],
    );
  }
}

class _ScResultRow extends StatelessWidget {
  const _ScResultRow({
    required this.title,
    required this.username,
    required this.artworkUrl,
    required this.durationSeconds,
    required this.onTap,
  });

  final String title;
  final String username;
  final String? artworkUrl;
  final int durationSeconds;
  final VoidCallback? onTap;

  String get _dur {
    final m = (durationSeconds ~/ 60).toString();
    final s = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: (artworkUrl != null && artworkUrl!.isNotEmpty)
                  ? Image.network(
                      artworkUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _ArtPlaceholder(),
                    )
                  : const _ArtPlaceholder(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmMono(
                      fontSize: 12,
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$username · $_dur',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      color: XeneTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.graphic_eq, color: XeneTheme.teal, size: 22),
          ],
        ),
      ),
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    color: const Color(0xFFE0E0E0),
    child: const Icon(Icons.music_note, size: 18, color: Color(0xFF999999)),
  );
}
