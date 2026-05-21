import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_domain/xene_domain.dart';
import 'auth_provider.dart';
import 'dio_provider.dart';

final artistsProvider = AsyncNotifierProvider<ArtistsNotifier, List<Artist>>(
  ArtistsNotifier.new,
);

class ArtistsNotifier extends AsyncNotifier<List<Artist>> {
  late Dio _dio;
  late String _userId;

  @override
  Future<List<Artist>> build() async {
    _userId = ref.watch(currentUserIdProvider);
    _dio = ref.watch(authenticatedDioProvider);
    return _fetchArtists();
  }

  Future<List<Artist>> _fetchArtists() async {
    debugPrint('[artistsProvider] Fetching artists for user=$_userId');
    try {
      final response = await _dio.get<List<dynamic>>('/artists');
      debugPrint(
        '[artistsProvider] Response status=${response.statusCode} count=${response.data?.length}',
      );

      final data = response.data ?? [];
      if (data.isEmpty) {
        debugPrint(
          '[artistsProvider] WARNING: /artists returned empty list — no artists in DB for user=$_userId',
        );
        return [];
      }

      final artists = <Artist>[];
      for (var i = 0; i < data.length; i++) {
        try {
          artists.add(Artist.fromJson(data[i] as Map<String, dynamic>));
        } catch (e) {
          debugPrint('[artistsProvider] ERROR parsing artist[$i]: $e');
          debugPrint('[artistsProvider] Skipping artist[$i]: ${data[i]}');
        }
      }

      debugPrint(
        '[artistsProvider] Parsed ${artists.length} artists successfully',
      );
      return artists;
    } on DioException catch (e) {
      debugPrint(
        '[artistsProvider] DioException status=${e.response?.statusCode} message=${e.message}',
      );
      debugPrint('[artistsProvider] Response body=${e.response?.data}');
      rethrow;
    } catch (e) {
      debugPrint('[artistsProvider] Unexpected error: $e');
      rethrow;
    }
  }

  Future<void> refresh() async {
    debugPrint('[artistsProvider] Refreshing artist list');
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchArtists);
  }

  Future<void> deleteArtist(String id) async {
    debugPrint('[artistsProvider] Deleting artist id=$id');
    try {
      await _dio.delete('/artists/$id');
      await refresh();
    } catch (e) {
      debugPrint('[artistsProvider] ERROR deleting artist: $e');
      rethrow;
    }
  }
}
