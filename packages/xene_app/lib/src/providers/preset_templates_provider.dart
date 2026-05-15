import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'preset_provider.dart';

const _kUserId = 'local_user';
const _kBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8080',
);

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

  @override
  Future<List<PresetTemplate>> build() async {
    _dio = _createDio();
    return _fetch();
  }

  Dio _createDio() {
    return Dio(
      BaseOptions(
        baseUrl: _kBackendUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-User-Id': _kUserId,
        },
      ),
    );
  }

  Future<List<PresetTemplate>> _fetch() async {
    final dio = _dio ??= _createDio();
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
    final dio = _dio ??= _createDio();
    await dio.post<Map<String, dynamic>>('/presets/templates', data: data);
    ref.invalidate(presetDialProvider);
    await refresh();
  }

  Future<void> updateTemplate(
    String originalSlug,
    Map<String, dynamic> data,
  ) async {
    final dio = _dio ??= _createDio();
    await dio.patch<Map<String, dynamic>>(
      '/presets/templates/$originalSlug',
      data: data,
    );
    ref.invalidate(presetDialProvider);
    await refresh();
  }
}
