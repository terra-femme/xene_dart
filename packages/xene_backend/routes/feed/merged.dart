import 'dart:async';
import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/services/soundcloud_service.dart';
import 'package:xene_backend/src/services/youtube_service.dart';
import 'package:xene_backend/src/services/beatport_service.dart';
import 'package:xene_backend/src/services/bandcamp_service.dart';
import 'package:xene_domain/xene_domain.dart';

/// ELI5: The "Master Chef" route. 
/// It takes orders for 10 different dishes, cooks them all at once, 
/// and puts them on one big plate sorted by time.
Future<Response> onRequest(RequestContext context) async {
  final params = context.request.uri.queryParametersAll;
  
  // Extract Query Params (mirroring feed.py)
  final scUsernames = params['sc'] ?? [];
  final scNames = params['sc_name'] ?? [];
  final bcUrls = params['bc_url'] ?? [];
  final bcNames = params['bc_name'] ?? [];
  final ytUrls = params['yt_url'] ?? [];
  final ytNames = params['yt_name'] ?? [];
  final bpIds = params['bp_label_id'] ?? [];
  final bpNames = params['bp_label_name'] ?? [];
  
  final page = int.tryParse(params['page']?.first ?? '1') ?? 1;
  final limit = int.tryParse(params['limit']?.first ?? '30') ?? 30;

  final scService = context.read<SoundCloudService>();
  final ytService = context.read<YouTubeService>();
  final bpService = context.read<BeatportService>();
  final bcService = context.read<BandcampService>();

  final allItems = <FeedItem>[];
  final tasks = <Future<List<FeedItem>>>[];

  // 1. Queue up the SoundCloud tasks
  for (var i = 0; i < scUsernames.length; i++) {
    final name = i < scNames.length ? scNames[i] : null;
    tasks.add(scService.getTracks(scUsernames[i], name));
  }

  // 2. Queue up the YouTube tasks
  for (var i = 0; i < ytUrls.length; i++) {
    final name = i < ytNames.length ? ytNames[i] : 'YouTube';
    tasks.add(ytService.getVideos(ytUrls[i], name));
  }

  // 3. Queue up the Bandcamp tasks
  for (var i = 0; i < bcUrls.length; i++) {
    final name = i < bcNames.length ? bcNames[i] : 'Bandcamp';
    tasks.add(bcService.getFeed(bcUrls[i], name));
  }

  // 4. Queue up the Beatport tasks
  for (var i = 0; i < bpIds.length; i++) {
    final name = i < bpNames.length ? bpNames[i] : 'Beatport';
    tasks.add(bpService.getLabelReleases(bpIds[i], labelName: name));
  }

  // Cook everything at once! (Parallel execution)
  final results = await Future.wait(tasks);
  for (final sublist in results) {
    allItems.addAll(sublist);
  }

  // Deduplicate and Sort
  final seenIds = <String>{};
  final uniqueItems = <FeedItem>[];

  // Sort by date descending
  allItems.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

  for (final item in allItems) {
    final key = '${item.platform}_${item.id}';
    if (!seenIds.contains(key)) {
      uniqueItems.add(item);
      seenIds.add(key);
    }
  }

  // Pagination
  final start = (page - 1) * limit;
  final end = start + limit;
  final paginated = uniqueItems.length > start 
      ? uniqueItems.sublist(start, end > uniqueItems.length ? uniqueItems.length : end)
      : <FeedItem>[];

  return Response.json(body: paginated.map((i) => i.toJson()).toList());
}
