import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as web;
import 'package:xene_domain/xene_domain.dart';

import 'bandcamp_open_button.dart';

class BandcampEmbed extends StatefulWidget {
  const BandcampEmbed({super.key, required this.item});

  final FeedItem item;

  @override
  State<BandcampEmbed> createState() => _BandcampEmbedState();
}

class _BandcampEmbedState extends State<BandcampEmbed> {
  static int _nextInstanceId = 0;
  late final String _viewId;
  late final String? _embedUrl;

  @override
  void initState() {
    super.initState();
    _viewId = 'bc-player-${_nextInstanceId++}';
    _embedUrl = _buildEmbedUrl(widget.item);

    ui.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = _embedUrl ?? 'about:blank'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.borderRadius = '8px';

      iframe.setAttribute('seamless', 'true');
      iframe.setAttribute('frameborder', '0');
      iframe.setAttribute('allow', 'autoplay; encrypted-media');

      return iframe;
    });
  }

  String? _buildEmbedUrl(FeedItem item) {
    if (item.mediaUrl != null &&
        item.mediaUrl!.contains('bandcamp.com/EmbeddedPlayer/')) {
      return item.mediaUrl;
    }

    final tralbumId = _tralbumId(item.id);
    if (tralbumId == null) return null;

    final type = item.contentType.toLowerCase() == 'track' ? 'track' : 'album';
    final itemUrl = Uri.encodeComponent(item.externalUrl);
    return 'https://bandcamp.com/EmbeddedPlayer/'
        '$type=$tralbumId/'
        'size=large/'
        'bgcol=111111/'
        'linkcol=629aa9/'
        'tracklist=true/'
        'transparent=true/'
        'artwork=small/'
        'minimal=false/'
        'link=$itemUrl/';
  }

  String? _tralbumId(String id) {
    final match = RegExp(r'^bc_(\d+)$').firstMatch(id);
    return match?.group(1);
  }

  @override
  Widget build(BuildContext context) {
    if (_embedUrl == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Open in Bandcamp',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              BandcampOpenButton(
                onTap: () => _launchBandcamp(widget.item.externalUrl),
              ),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.expand(child: HtmlElementView(viewType: _viewId)),
    );
  }

  Future<void> _launchBandcamp(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
