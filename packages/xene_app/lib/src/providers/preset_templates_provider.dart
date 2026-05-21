import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dio_provider.dart';
import 'preset_provider.dart';

@immutable
class PresetTemplate {
  const PresetTemplate({
    required this.slug,
    required this.name,
    required this.notchIndex,
    required this.themeColor,
    required this.isDefault,
    required this.enabled,
    this.description,
    this.version,
  });

  final String slug;
  final String name;
  final int notchIndex;
  final String themeColor;
  final bool isDefault;
  final bool enabled;
  final String? description;
  final int? version;

  factory PresetTemplate.fromJson(Map<String, dynamic> json) {
    return PresetTemplate(
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      notchIndex: json['notchIndex'] as int? ?? 0,
      themeColor: json['themeColor'] as String? ?? '#222222',
      isDefault: json['isDefault'] == true,
      enabled: json['enabled'] != false,
      version: json['version'] as int?,
    );
  }
}

final presetTemplatesProvider =
    AsyncNotifierProvider<PresetTemplatesNotifier, List<PresetTemplate>>(
      PresetTemplatesNotifier.new,
    );

class PresetTemplatesNotifier extends AsyncNotifier<List<PresetTemplate>> {
  Dio? _dio;

  Dio _getDio() {
    _dio ??= ref.read(authenticatedDioProvider);
    return _dio!;
  }

  @override
  Future<List<PresetTemplate>> build() async {
    _dio = ref.watch(authenticatedDioProvider);
    return _fetch();
  }

  Future<List<PresetTemplate>> _fetch() async {
    final dio = _getDio();
    final response = await dio.get<List<dynamic>>('/presets/templates');
    final rows = response.data ?? [];
    return rows
        .cast<Map<String, dynamic>>()
        .map(PresetTemplate.fromJson)
        .toList();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> create(Map<String, dynamic> data) async {
    final dio = _getDio();
    await dio.post<Map<String, dynamic>>('/presets/templates', data: data);
    ref.invalidate(presetDialProvider);
    await refresh();
  }

  Future<void> updateTemplate(
    String originalSlug,
    Map<String, dynamic> data,
  ) async {
    final dio = _getDio();
    await dio.patch<Map<String, dynamic>>(
      '/presets/templates/$originalSlug',
      data: data,
    );
    ref.invalidate(presetDialProvider);
    await refresh();
  }
}
