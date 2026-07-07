import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xene_domain/xene_domain.dart';

import 'bandcamp_open_button.dart';

class BandcampEmbed extends StatelessWidget {
  const BandcampEmbed({super.key, required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'BANDCAMP',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              BandcampOpenButton(onTap: () => _launchBandcamp(item.externalUrl)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchBandcamp(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
