import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xene_app/src/providers/dio_provider.dart';
import 'package:xene_app/src/providers/preset_provider.dart';

@immutable
class ArticleItem {
  const ArticleItem({
    required this.title,
    required this.url,
    required this.snippet,
    this.source,
    this.imageUrl,
    this.publishedAt,
    this.artistId,
  });

  final String title;
  final String url;
  final String snippet;
  final String? source;
  final String? imageUrl;
  final DateTime? publishedAt;
  final String? artistId;

  factory ArticleItem.fromJson(Map<String, dynamic> json) {
    final pubAtRaw = json['published_at'] as String?;
    return ArticleItem(
      title: (json['title'] as String?)?.trim() ?? '',
      url: (json['url'] as String?)?.trim() ?? '',
      snippet: (json['snippet'] as String?)?.trim() ?? '',
      source: json['source'] as String?,
      imageUrl: (json['image_url'] as String?)?.trim(),
      publishedAt: pubAtRaw != null ? DateTime.tryParse(pubAtRaw) : null,
      artistId: json['artist_id'] as String?,
    );
  }
}

// ─── Magazine Cover Models ───────────────────────────────────────────────────

@immutable
class MagazineMotionLayer {
  const MagazineMotionLayer({
    required this.id,
    required this.type,
    required this.url,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.loop,
    this.opacity = 1.0,
    this.speed = 1.0,
  });

  final String id;
  final String type; // 'lottie' | 'shader'
  final String url;
  final double x; // 0.0–1.0 fraction of cover width
  final double y; // 0.0–1.0 fraction of cover height
  final double width; // fraction
  final double height; // fraction
  final bool loop;
  final double opacity; // 0.0–1.0
  final double speed;   // playback rate multiplier

  factory MagazineMotionLayer.fromJson(Map<String, dynamic> json) {
    return MagazineMotionLayer(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'lottie',
      url: json['url'] as String? ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 0,
      height: (json['height'] as num?)?.toDouble() ?? 0,
      loop: json['loop'] as bool? ?? true,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

@immutable
class MagazineHotspot {
  const MagazineHotspot({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.title,
    this.body,
    this.articleUrl,
  });

  final String id;
  final double x; // 0.0–1.0 fraction of cover width
  final double y; // 0.0–1.0 fraction of cover height
  final double width; // fraction
  final double height; // fraction
  final String title;
  final String? body;
  final String? articleUrl;

  factory MagazineHotspot.fromJson(Map<String, dynamic> json) {
    return MagazineHotspot(
      id: json['id'] as String? ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 0,
      height: (json['height'] as num?)?.toDouble() ?? 0,
      title: json['title'] as String? ?? '',
      body: json['body'] as String?,
      articleUrl: json['article_url'] as String?,
    );
  }
}

@immutable
class MagazineCover {
  const MagazineCover({
    required this.id,
    required this.title,
    required this.backgroundImageUrl,
    this.dek,
    this.fallbackImageUrl,
    this.altText,
    this.aspectRatio = '3:4',
    this.motionLayers = const [],
    this.hotspots = const [],
  });

  final String id;
  final String title;
  final String backgroundImageUrl;
  final String? dek;
  final String? fallbackImageUrl;
  final String? altText;
  final String aspectRatio; // e.g. '3:4'
  final List<MagazineMotionLayer> motionLayers;
  final List<MagazineHotspot> hotspots;

  double get aspectRatioValue {
    final parts = aspectRatio.split(':');
    if (parts.length != 2) return 3 / 4;
    final w = double.tryParse(parts[0]) ?? 3;
    final h = double.tryParse(parts[1]) ?? 4;
    return w / h;
  }

  factory MagazineCover.fromJson(Map<String, dynamic> json) {
    final layers = (json['motion_layers'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(MagazineMotionLayer.fromJson)
            .toList() ??
        [];
    final spots = (json['hotspots'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(MagazineHotspot.fromJson)
            .toList() ??
        [];
    return MagazineCover(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      backgroundImageUrl: json['background_image_url'] as String? ?? '',
      dek: json['dek'] as String?,
      fallbackImageUrl: json['fallback_image_url'] as String?,
      altText: json['alt_text'] as String?,
      aspectRatio: json['aspect_ratio'] as String? ?? '3:4',
      motionLayers: layers,
      hotspots: spots,
    );
  }
}

// ─── Providers ───────────────────────────────────────────────────────────────

/// Fetches curated Feature Strip articles from Supabase.
/// Managed entirely by the admin dashboard — no press scout dependency.
/// Falls back to empty list when the table doesn't exist yet.
final featuredArticlesProvider = FutureProvider.autoDispose<List<ArticleItem>>((
  ref,
) async {
  debugPrint('[featuredArticlesProvider] Fetching featured articles');
  try {
    final data = await Supabase.instance.client
        .from('featured_articles')
        .select()
        .eq('active', true)
        .order('sort_order', ascending: true)
        .limit(20);
    final items = (data as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(ArticleItem.fromJson)
        .where((a) => a.title.isNotEmpty)
        .toList();
    debugPrint(
      '[featuredArticlesProvider] Loaded ${items.length} featured articles',
    );
    return items;
  } catch (e) {
    debugPrint('[featuredArticlesProvider] Error: $e');
    return const [];
  }
});

/// Fetches press articles for the currently active preset.
/// Auto-refetches whenever [activePresetSlugProvider] changes.
final presetArticlesProvider = FutureProvider.autoDispose<List<ArticleItem>>((
  ref,
) async {
  final slug = ref.watch(activePresetSlugProvider);
  debugPrint('[presetArticlesProvider] Fetching articles for preset=$slug');

  final dio = ref.watch(authenticatedDioProvider);

  try {
    final response = await dio.get<List<dynamic>>(
      '/presets/articles',
      queryParameters: {'preset': slug, 'limit': 12},
    );
    final data = response.data ?? [];
    debugPrint(
      '[presetArticlesProvider] Raw response: ${data.length} items for preset=$slug',
    );
    final items = data
        .whereType<Map<String, dynamic>>()
        .map(ArticleItem.fromJson)
        .where((a) => a.title.isNotEmpty)
        .toList();
    debugPrint(
      '[presetArticlesProvider] Filtered to ${items.length} valid articles for preset=$slug',
    );
    return items;
  } catch (e) {
    debugPrint(
      '[presetArticlesProvider] Error fetching articles for $slug: $e',
    );
    return const [];
  }
});

// ─── Xene Article Models ──────────────────────────────────────────────────────

@immutable
class XeneArticleBlock {
  const XeneArticleBlock({
    required this.id,
    required this.type,
    required this.data,
  });

  final String id;
  final String type; // 'text'|'quote'|'image'|'video'|'voice_note'|'spacer'
  final Map<String, dynamic> data;

  // Typed accessors — all return null when the field is absent
  String? get heading => data['heading'] as String?;
  String? get body => data['body'] as String?;
  String? get text => data['text'] as String?;
  String? get attribution => data['attribution'] as String?;
  String? get url => data['url'] as String?;
  String? get caption => data['caption'] as String?;
  String? get aspect => data['aspect'] as String?;
  String? get thumbnailUrl => data['thumbnail_url'] as String?;
  String? get provider => data['provider'] as String?;
  int? get durationSeconds => (data['duration_seconds'] as num?)?.toInt();
  String? get transcript => data['transcript'] as String?;
  String? get size => data['size'] as String?; // 'sm'|'md'|'lg'

  factory XeneArticleBlock.fromJson(Map<String, dynamic> json) {
    return XeneArticleBlock(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      data: Map<String, dynamic>.from(json),
    );
  }
}

@immutable
class XeneArticle {
  const XeneArticle({
    required this.id,
    required this.slug,
    required this.title,
    required this.blocks,
    this.dek,
    this.author,
    this.layoutTemplate = 'editorial',
    this.sectionLabel,
    this.coverImageUrl,
    this.themeColor,
    this.publishedAt,
  });

  final String id;
  final String slug;
  final String title;
  final String? dek;
  final String? author;
  final String layoutTemplate;
  final String? sectionLabel;
  final String? coverImageUrl;
  final String? themeColor; // hex e.g. '#00A88F'
  final List<XeneArticleBlock> blocks;
  final DateTime? publishedAt;

  factory XeneArticle.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['blocks'] as List<dynamic>? ?? [];
    final blocks = rawBlocks
        .whereType<Map<String, dynamic>>()
        .map(XeneArticleBlock.fromJson)
        .toList();
    final pubAtRaw = json['published_at'] as String?;
    return XeneArticle(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      dek: json['dek'] as String?,
      author: json['author'] as String?,
      layoutTemplate: json['layout_template'] as String? ?? 'editorial',
      sectionLabel: json['section_label'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      themeColor: json['theme_color'] as String?,
      blocks: blocks,
      publishedAt: pubAtRaw != null ? DateTime.tryParse(pubAtRaw) : null,
    );
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

/// Fetches a published Xene article by slug directly from Supabase.
/// Returns null when the article doesn't exist or isn't published.
final xeneArticleProvider =
    FutureProvider.autoDispose.family<XeneArticle?, String>((ref, slug) async {
  debugPrint('[xeneArticleProvider] Fetching article slug=$slug');
  try {
    final data = await Supabase.instance.client
        .from('xene_articles')
        .select()
        .eq('slug', slug)
        .eq('status', 'published')
        .maybeSingle();
    if (data == null) {
      debugPrint('[xeneArticleProvider] Article not found or unpublished: $slug');
      return null;
    }
    final article = XeneArticle.fromJson(data);
    debugPrint(
      '[xeneArticleProvider] Loaded: ${article.title} '
      'blocks=${article.blocks.length} template=${article.layoutTemplate}',
    );
    return article;
  } catch (e) {
    debugPrint('[xeneArticleProvider] Error fetching $slug: $e');
    rethrow;
  }
});

/// Fetches the currently active magazine cover from the backend.
/// Returns null when no cover is configured — the UI falls back gracefully.
final magazineCoverProvider = FutureProvider.autoDispose<MagazineCover?>((
  ref,
) async {
  debugPrint('[magazineCoverProvider] Fetching active magazine cover');
  final dio = ref.watch(authenticatedDioProvider);
  try {
    final response = await dio.get<Map<String, dynamic>>(
      '/presets/magazine_cover',
    );
    if (response.data == null || response.data!.isEmpty) {
      debugPrint('[magazineCoverProvider] No active cover returned');
      return null;
    }
    final cover = MagazineCover.fromJson(response.data!);
    debugPrint(
      '[magazineCoverProvider] Cover loaded: id=${cover.id} title=${cover.title} '
      'layers=${cover.motionLayers.length} hotspots=${cover.hotspots.length}',
    );
    return cover;
  } catch (e) {
    debugPrint('[magazineCoverProvider] Error fetching cover: $e');
    return null;
  }
});
