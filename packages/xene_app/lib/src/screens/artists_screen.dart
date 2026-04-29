import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_domain/xene_domain.dart';
import '../widgets/platform_badge.dart';

/// ELI5: The "Artist Library."
/// A simple, searchable list of every artist you follow.
class ArtistsScreen extends ConsumerStatefulWidget {
  const ArtistsScreen({super.key});

  @override
  ConsumerState<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends ConsumerState<ArtistsScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    // In a full app, we'd have an artistsProvider. 
    // For this scaffold, we'll use a placeholder list.
    final List<Artist> artists = []; 

    final filteredArtists = artists
        .where((a) => a.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search artists...',
              prefixIcon: const Icon(Icons.search, color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: filteredArtists.isEmpty 
            ? const Center(child: Text('No artists found', style: TextStyle(color: Colors.white24)))
            : ListView.separated(
                itemCount: filteredArtists.length,
                separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
                itemBuilder: (context, index) {
                  final artist = filteredArtists[index];
                  return ListTile(
                    title: Text(artist.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: Text('${artist.entityType.toUpperCase()} • ${artist.identityConfidence} CONFIDENCE', 
                      style: const TextStyle(fontSize: 10, color: Colors.white38)),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white24),
                    onTap: () {
                      // Navigate to Detail
                    },
                  );
                },
              ),
        ),
      ],
    );
  }
  }

