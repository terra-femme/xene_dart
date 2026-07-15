import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xene_app/src/providers/config_provider.dart';

class RemoteConfig {
  static const String _configUrl =
      'https://raw.githubusercontent.com/terra-femme/xene_dart/main/packages/xene_app/lib/config.json';
  static const String _cacheKey = 'xene_remote_config';

  static final _dio = Dio();
  static bool _isLocalUrl(String url) =>
      url.contains('localhost') ||
      url.contains('127.0.0.1') ||
      url.contains('10.0.2.2');

  static String _productionUrl(String url) =>
      _isLocalUrl(url) ? kProductionBackendUrl : url;

  static Future<String> getBackendUrl() async {
    // DEVELOPMENT: If running with --define=LOCAL_BACKEND=true,
    // connect to local backend instead of remote.
    // Usage: flutter run -d web --define=LOCAL_BACKEND=true
    const bool isLocalBackend = bool.fromEnvironment(
      'LOCAL_BACKEND',
      defaultValue: false,
    );
    if (isLocalBackend) {
      print(
        '[RemoteConfig] LOCAL_BACKEND mode enabled — using http://localhost:8080',
      );
      return 'http://localhost:8080';
    }

    try {
      // Try to fetch latest config from GitHub
      final config = await _fetchRemoteConfig();
      if (config != null) {
        final backend = config['backend'] as Map<String, dynamic>?;
        return _productionUrl(
          backend?['url'] as String? ??
              config['backend_url'] as String? ??
              kProductionBackendUrl,
        );
      }
    } catch (e) {
      print('[RemoteConfig] Failed to fetch from GitHub: $e');
    }

    // Fall back to cached config
    final cached = await _getCachedConfig();
    if (cached != null) {
      final backend = cached['backend'] as Map<String, dynamic>?;
      return _productionUrl(
        backend?['url'] as String? ??
            cached['backend_url'] as String? ??
            kProductionBackendUrl,
      );
    }

    // Last resort: use hardcoded fallback (Azure production)
    return kProductionBackendUrl;
  }

  static Future<Map<String, dynamic>?> _fetchRemoteConfig() async {
    try {
      final response = await _dio.get<String>(
        _configUrl,
        options: Options(connectTimeout: const Duration(seconds: 5)),
      );

      if (response.statusCode == 200 && response.data != null) {
        final config = jsonDecode(response.data!) as Map<String, dynamic>;
        // Cache the config
        await _cacheConfig(config);
        return config;
      }
    } catch (e) {
      print('[RemoteConfig] Error fetching config: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _getCachedConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        return jsonDecode(cached) as Map<String, dynamic>;
      }
    } catch (e) {
      print('[RemoteConfig] Error reading cache: $e');
    }
    return null;
  }

  static Future<void> _cacheConfig(Map<String, dynamic> config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final withTimestamp = {
        ...config,
        '_cachedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_cacheKey, jsonEncode(withTimestamp));
    } catch (e) {
      print('[RemoteConfig] Error caching config: $e');
    }
  }
}
