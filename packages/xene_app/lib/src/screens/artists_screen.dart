import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_domain/xene_domain.dart';

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
              hintText: 'SEARCH ARTISTS...',
              hintStyle: const TextStyle(fontFamily: 'Teko', fontSize: 14, color: Color(0xFF888888)),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF888888)),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: filteredArtists.isEmpty 
            ? const Center(child: Text('NO ARTISTS FOUND', style: TextStyle(fontFamily: 'Teko', color: Color(0xFF888888))))
            : ListView.separated(
                itemCount: filteredArtists.length,
                separatorBuilder: (context, index) => const Divider(color: Color(0xFFF5F5F5), height: 1),
                itemBuilder: (context, index) {
                  final artist = filteredArtists[index];
                  return ListTile(
                    title: Text(artist.name.toUpperCase(), style: const TextStyle(fontFamily: 'Teko', color: Colors.black, fontSize: 18)),
                    subtitle: Text('${artist.entityType.toUpperCase()} • ${artist.identityConfidence} CONFIDENCE', 
                      style: const TextStyle(fontFamily: 'Archivo', fontSize: 10, color: Color(0xFF888888))),
                    trailing: const Icon(Icons.chevron_right, color: Color(0xFF888888)),
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
