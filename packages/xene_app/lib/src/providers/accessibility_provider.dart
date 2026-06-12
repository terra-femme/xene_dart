import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kTextScale = 'a11y_text_scale';
const _kReduceMotion = 'a11y_reduce_motion';
const _kHighContrast = 'a11y_high_contrast';

class AccessibilitySettings {
  const AccessibilitySettings({
    this.textScaleOverride = 1.0,
    this.reduceMotion = false,
    this.highContrast = false,
  });

  final double textScaleOverride;
  final bool reduceMotion;
  final bool highContrast;

  AccessibilitySettings copyWith({
    double? textScaleOverride,
    bool? reduceMotion,
    bool? highContrast,
  }) => AccessibilitySettings(
    textScaleOverride: textScaleOverride ?? this.textScaleOverride,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    highContrast: highContrast ?? this.highContrast,
  );
}

final accessibilityProvider =
    StateNotifierProvider<AccessibilityNotifier, AccessibilitySettings>(
      AccessibilityNotifier.new,
    );

class AccessibilityNotifier extends StateNotifier<AccessibilitySettings> {
  AccessibilityNotifier(this.ref) : super(const AccessibilitySettings()) {
    Future.microtask(_load);
  }

  final Ref ref;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        state = AccessibilitySettings(
          textScaleOverride: prefs.getDouble(_kTextScale) ?? 1.0,
          reduceMotion: prefs.getBool(_kReduceMotion) ?? false,
          highContrast: prefs.getBool(_kHighContrast) ?? false,
        );
      }
    } catch (e) {
      debugPrint('[accessibility] failed to load prefs: $e');
    }
  }

  Future<void> setTextScale(double value) async {
    state = state.copyWith(textScaleOverride: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kTextScale, value);
  }

  Future<void> setReduceMotion(bool value) async {
    state = state.copyWith(reduceMotion: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kReduceMotion, value);
  }

  Future<void> setHighContrast(bool value) async {
    state = state.copyWith(highContrast: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHighContrast, value);
  }
}
