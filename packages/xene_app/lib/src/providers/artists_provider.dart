import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xene_domain/xene_domain.dart';

const _kUserId = 'local_user';

final artistsProvider = AsyncNotifierProvider<ArtistsNotifier, List<Artist>>(ArtistsNotifier.new);

class ArtistsNotifier extends AsyncNotifier<List<Artist>> {
  late final Dio _dio;

  @override
  Future<List<Artist>> build() async {
    _dio = Dio(BaseOptions(
      baseUrl: 'http://127.0.0.1:8080',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-User-Id': _kUserId,
      },
    ));
    return _fetchArtists();
  }

  Future<List<Artist>> _fetchArtists() async {
    debugPrint('[artistsProvider] Fetching artists for user=$_kUserId');
    try {
      final response = await _dio.get<List<dynamic>>('/artists');
      debugPrint('[artistsProvider] Response status=${response.statusCode} count=${response.data?.length}');

      final data = response.data ?? [];
      if (data.isEmpty) {
        debugPrint('[artistsProvider] WARNING: /artists returned empty list — no artists in DB for user=$_kUserId');
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

      debugPrint('[artistsProvider] Parsed ${artists.length} artists successfully');
      return artists;
    } on DioException catch (e) {
      debugPrint('[artistsProvider] DioException status=${e.response?.statusCode} message=${e.message}');
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
