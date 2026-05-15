import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kUserId = 'local_user';
const _kBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8080',
);

@immutable
class PresetSlot {
  const PresetSlot({
    required this.slug,
    required this.name,
    required this.notchIndex,
    required this.themeColor,
    this.description,
    this.isDefault = false,
    this.isCustom = false,
    this.enabled = true,
  });

  final String slug;
  final String name;
  final int notchIndex;
  final Color themeColor;
  final String? description;
  final bool isDefault;
  final bool isCustom;
  final bool enabled;

  factory PresetSlot.fromJson(Map<String, dynamic> json) {
    return PresetSlot(
      slug: json['slug'] as String,
      name: json['name'] as String? ?? 'PRESET',
      description: json['description'] as String?,
      notchIndex: json['notchIndex'] as int? ?? 0,
      themeColor: _parseHexColor(json['themeColor'] as String?),
      isDefault: json['isDefault'] == true,
      isCustom: json['isCustom'] == true,
      enabled: json['enabled'] != false,
    );
  }
}

@immutable
class PresetDialState {
  const PresetDialState({
    required this.slots,
    required this.activePresetSlug,
    required this.defaultPresetSlug,
  });

  final List<PresetSlot> slots;
  final String activePresetSlug;
  final String defaultPresetSlug;

  PresetSlot get activeSlot {
    return slots.firstWhere(
      (slot) => slot.slug == activePresetSlug,
      orElse: () => slots.firstWhere(
        (slot) => slot.slug == defaultPresetSlug,
        orElse: () => slots.first,
      ),
    );
  }

  PresetDialState copyWith({
    List<PresetSlot>? slots,
    String? activePresetSlug,
    String? defaultPresetSlug,
  }) {
    return PresetDialState(
      slots: slots ?? this.slots,
      activePresetSlug: activePresetSlug ?? this.activePresetSlug,
      defaultPresetSlug: defaultPresetSlug ?? this.defaultPresetSlug,
    );
  }
}

final presetDialProvider =
    AsyncNotifierProvider<PresetDialNotifier, PresetDialState>(
      PresetDialNotifier.new,
    );

const kDefaultPresetSlug = 'dnb-foundations';

final activePresetSlugProvider = Provider<String>((ref) {
  return ref.watch(presetDialProvider).maybeWhen(
    data: (state) => state.activePresetSlug,
    orElse: () => kDefaultPresetSlug,
  );
});

class PresetDialNotifier extends AsyncNotifier<PresetDialState> {
  Dio? _dio;

  @override
  Future<PresetDialState> build() async {
    _dio = _createDio();
    return _fetchDial();
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

  Future<PresetDialState> _fetchDial() async {
    final dio = _dio ??= _createDio();
    final response = await dio.get<Map<String, dynamic>>('/presets');
    final data = response.data ?? {};
    final slots =
        (data['slots'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(PresetSlot.fromJson)
            .where((slot) => slot.enabled)
            .toList()
          ..sort((a, b) => a.notchIndex.compareTo(b.notchIndex));

    if (slots.isEmpty) {
      return const PresetDialState(
        slots: [
          PresetSlot(
            slug: 'custom',
            name: 'CUSTOM',
            notchIndex: 0,
            themeColor: Color(0xFF222222),
            isCustom: true,
          ),
        ],
        activePresetSlug: 'custom',
        defaultPresetSlug: 'custom',
      );
    }

    final defaultSlug =
        data['defaultPresetSlug'] as String? ?? slots.first.slug;
    final activeSlug = data['activePresetSlug'] as String? ?? defaultSlug;
    return PresetDialState(
      slots: slots,
      activePresetSlug: activeSlug,
      defaultPresetSlug: defaultSlug,
    );
  }

  Future<void> selectPreset(String slug) async {
    final previous = state.valueOrNull;
    if (previous == null || previous.activePresetSlug == slug) return;

    state = AsyncData(previous.copyWith(activePresetSlug: slug));

    try {
      final dio = _dio ??= _createDio();
      await dio.post<Map<String, dynamic>>(
        '/presets',
        data: {'activePresetSlug': slug},
      );
    } catch (e) {
      debugPrint('[presetDialProvider] Failed to persist selection: $e');
    }
  }
}

Color _parseHexColor(String? value) {
  final hex = (value ?? '#222222').replaceFirst('#', '');
  final parsed = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return Color(parsed ?? 0xFF222222);
}
