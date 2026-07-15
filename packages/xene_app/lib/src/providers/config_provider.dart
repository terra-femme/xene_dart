import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kProductionBackendUrl =
    'https://xene-backend.yellowwater-2ccd556b.eastus.azurecontainerapps.io';

bool _isLocalUrl(String url) =>
    url.contains('localhost') ||
    url.contains('127.0.0.1') ||
    url.contains('10.0.2.2');

class AppConfig {
  const AppConfig({
    required this.backendUrl,
    required this.authRedirectUrl,
    required this.configRepoUrl,
    required this.dioTimeoutConnectSeconds,
    required this.dioTimeoutReceiveSeconds,
    required this.capacityCheckTimeoutConnectSeconds,
    required this.capacityCheckTimeoutReceiveSeconds,
    required this.monitorTimeoutConnectSeconds,
    required this.monitorTimeoutReceiveSeconds,
    required this.monitorPollIntervalSeconds,
    required this.presetSourcesTimeoutMinutes,
    required this.feedWindowLimit,
    required this.feedArchivePageLimit,
    required this.feedFullArchivePageLimit,
    required this.cacheRecentFastMinutes,
    required this.cacheRecentBcMinutes,
    required this.cacheArchiveMinutes,
    required this.userCap,
    required this.trackAnalysisMaxAttempts,
    required this.soundcloudConnectionPollIntervalSeconds,
    required this.soundcloudConnectionPollTimeoutMinutes,
    required this.searchDebounceMilliseconds,
    required this.trackAnalysisPollIntervalSeconds,
    required this.feedFetchDelayMilliseconds,
  });

  final String backendUrl;
  final String authRedirectUrl;
  final String configRepoUrl;
  final int dioTimeoutConnectSeconds;
  final int dioTimeoutReceiveSeconds;
  final int capacityCheckTimeoutConnectSeconds;
  final int capacityCheckTimeoutReceiveSeconds;
  final int monitorTimeoutConnectSeconds;
  final int monitorTimeoutReceiveSeconds;
  final int monitorPollIntervalSeconds;
  final int presetSourcesTimeoutMinutes;
  final int feedWindowLimit;
  final int feedArchivePageLimit;
  final int feedFullArchivePageLimit;
  final int cacheRecentFastMinutes;
  final int cacheRecentBcMinutes;
  final int cacheArchiveMinutes;
  final int userCap;
  final int trackAnalysisMaxAttempts;
  final int soundcloudConnectionPollIntervalSeconds;
  final int soundcloudConnectionPollTimeoutMinutes;
  final int searchDebounceMilliseconds;
  final int trackAnalysisPollIntervalSeconds;
  final int feedFetchDelayMilliseconds;

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final backend = json['backend'] as Map<String, dynamic>? ?? {};
    final httpConfig = json['http'] as Map<String, dynamic>? ?? {};
    final feedConfig = json['feed'] as Map<String, dynamic>? ?? {};
    final cacheConfig = json['cache'] as Map<String, dynamic>? ?? {};
    final limitsConfig = json['limits'] as Map<String, dynamic>? ?? {};
    final configSection = json['config'] as Map<String, dynamic>? ?? {};

    return AppConfig(
      backendUrl: backend['url'] as String? ?? kProductionBackendUrl,
      authRedirectUrl:
          backend['auth_redirect_url'] as String? ?? kProductionBackendUrl,
      configRepoUrl:
          configSection['repo_url'] as String? ??
          'https://raw.githubusercontent.com/terra-femme/xene_dart/main/packages/xene_app/lib/config.json',
      dioTimeoutConnectSeconds:
          httpConfig['dio_timeout_connect_seconds'] as int? ?? 30,
      dioTimeoutReceiveSeconds:
          httpConfig['dio_timeout_receive_seconds'] as int? ?? 30,
      capacityCheckTimeoutConnectSeconds:
          httpConfig['capacity_check_timeout_connect_seconds'] as int? ?? 5,
      capacityCheckTimeoutReceiveSeconds:
          httpConfig['capacity_check_timeout_receive_seconds'] as int? ?? 8,
      monitorTimeoutConnectSeconds:
          httpConfig['monitor_timeout_connect_seconds'] as int? ?? 5,
      monitorTimeoutReceiveSeconds:
          httpConfig['monitor_timeout_receive_seconds'] as int? ?? 8,
      monitorPollIntervalSeconds:
          httpConfig['monitor_poll_interval_seconds'] as int? ?? 15,
      presetSourcesTimeoutMinutes:
          httpConfig['preset_sources_timeout_minutes'] as int? ?? 5,
      feedWindowLimit: feedConfig['window_limit'] as int? ?? 30,
      feedArchivePageLimit: feedConfig['archive_page_limit'] as int? ?? 16,
      feedFullArchivePageLimit:
          feedConfig['full_archive_page_limit'] as int? ?? 50,
      cacheRecentFastMinutes: cacheConfig['recent_fast_minutes'] as int? ?? 5,
      cacheRecentBcMinutes: cacheConfig['recent_bc_minutes'] as int? ?? 5,
      cacheArchiveMinutes: cacheConfig['archive_minutes'] as int? ?? 10,
      userCap: limitsConfig['user_cap'] as int? ?? 2000,
      trackAnalysisMaxAttempts:
          limitsConfig['track_analysis_max_attempts'] as int? ?? 6,
      soundcloudConnectionPollIntervalSeconds:
          limitsConfig['soundcloud_connection_poll_interval_seconds'] as int? ??
          3,
      soundcloudConnectionPollTimeoutMinutes:
          limitsConfig['soundcloud_connection_poll_timeout_minutes'] as int? ??
          5,
      searchDebounceMilliseconds:
          limitsConfig['search_debounce_milliseconds'] as int? ?? 500,
      trackAnalysisPollIntervalSeconds:
          limitsConfig['track_analysis_poll_interval_seconds'] as int? ?? 2,
      feedFetchDelayMilliseconds:
          limitsConfig['feed_fetch_delay_milliseconds'] as int? ?? 150,
    );
  }
}

class ConfigNotifier extends AsyncNotifier<AppConfig> {
  static const String _cacheKey = 'xene_app_config';
  static final _dio = Dio();

  @override
  Future<AppConfig> build() async {
    // DEVELOPMENT: If running with --define=LOCAL_BACKEND=true,
    // use local backend; other values load from config.json.
    const bool isLocalBackend = bool.fromEnvironment(
      'LOCAL_BACKEND',
      defaultValue: false,
    );

    try {
      // Try to fetch latest config from GitHub.
      final remoteConfig = await _fetchRemoteConfig();
      if (remoteConfig != null) {
        var config = AppConfig.fromJson(remoteConfig);
        // Override backend URL if LOCAL_BACKEND is set.
        if (isLocalBackend) {
          config = AppConfig(
            backendUrl: 'http://localhost:8080',
            authRedirectUrl: config.authRedirectUrl,
            configRepoUrl: config.configRepoUrl,
            dioTimeoutConnectSeconds: config.dioTimeoutConnectSeconds,
            dioTimeoutReceiveSeconds: config.dioTimeoutReceiveSeconds,
            capacityCheckTimeoutConnectSeconds:
                config.capacityCheckTimeoutConnectSeconds,
            capacityCheckTimeoutReceiveSeconds:
                config.capacityCheckTimeoutReceiveSeconds,
            monitorTimeoutConnectSeconds: config.monitorTimeoutConnectSeconds,
            monitorTimeoutReceiveSeconds: config.monitorTimeoutReceiveSeconds,
            monitorPollIntervalSeconds: config.monitorPollIntervalSeconds,
            presetSourcesTimeoutMinutes: config.presetSourcesTimeoutMinutes,
            feedWindowLimit: config.feedWindowLimit,
            feedArchivePageLimit: config.feedArchivePageLimit,
            feedFullArchivePageLimit: config.feedFullArchivePageLimit,
            cacheRecentFastMinutes: config.cacheRecentFastMinutes,
            cacheRecentBcMinutes: config.cacheRecentBcMinutes,
            cacheArchiveMinutes: config.cacheArchiveMinutes,
            userCap: config.userCap,
            trackAnalysisMaxAttempts: config.trackAnalysisMaxAttempts,
            soundcloudConnectionPollIntervalSeconds:
                config.soundcloudConnectionPollIntervalSeconds,
            soundcloudConnectionPollTimeoutMinutes:
                config.soundcloudConnectionPollTimeoutMinutes,
            searchDebounceMilliseconds: config.searchDebounceMilliseconds,
            trackAnalysisPollIntervalSeconds:
                config.trackAnalysisPollIntervalSeconds,
            feedFetchDelayMilliseconds: config.feedFetchDelayMilliseconds,
          );
        } else {
          config = _sanitizeProductionConfig(config);
        }
        return config;
      }
    } catch (e) {
      print('[ConfigNotifier] Failed to fetch from GitHub: $e');
    }

    // Fall back to cached config.
    final cached = await _getCachedConfig();
    if (cached != null) {
      var config = AppConfig.fromJson(cached);
      if (isLocalBackend) {
        config = AppConfig(
          backendUrl: 'http://localhost:8080',
          authRedirectUrl: config.authRedirectUrl,
          configRepoUrl: config.configRepoUrl,
          dioTimeoutConnectSeconds: config.dioTimeoutConnectSeconds,
          dioTimeoutReceiveSeconds: config.dioTimeoutReceiveSeconds,
          capacityCheckTimeoutConnectSeconds:
              config.capacityCheckTimeoutConnectSeconds,
          capacityCheckTimeoutReceiveSeconds:
              config.capacityCheckTimeoutReceiveSeconds,
          monitorTimeoutConnectSeconds: config.monitorTimeoutConnectSeconds,
          monitorTimeoutReceiveSeconds: config.monitorTimeoutReceiveSeconds,
          monitorPollIntervalSeconds: config.monitorPollIntervalSeconds,
          presetSourcesTimeoutMinutes: config.presetSourcesTimeoutMinutes,
          feedWindowLimit: config.feedWindowLimit,
          feedArchivePageLimit: config.feedArchivePageLimit,
          feedFullArchivePageLimit: config.feedFullArchivePageLimit,
          cacheRecentFastMinutes: config.cacheRecentFastMinutes,
          cacheRecentBcMinutes: config.cacheRecentBcMinutes,
          cacheArchiveMinutes: config.cacheArchiveMinutes,
          userCap: config.userCap,
          trackAnalysisMaxAttempts: config.trackAnalysisMaxAttempts,
          soundcloudConnectionPollIntervalSeconds:
              config.soundcloudConnectionPollIntervalSeconds,
          soundcloudConnectionPollTimeoutMinutes:
              config.soundcloudConnectionPollTimeoutMinutes,
          searchDebounceMilliseconds: config.searchDebounceMilliseconds,
          trackAnalysisPollIntervalSeconds:
              config.trackAnalysisPollIntervalSeconds,
          feedFetchDelayMilliseconds: config.feedFetchDelayMilliseconds,
        );
      } else {
        config = _sanitizeProductionConfig(config);
      }
      return config;
    }

    // Last resort: use defaults (should rarely happen in production).
    return AppConfig.fromJson({});
  }

  Future<Map<String, dynamic>?> _fetchRemoteConfig() async {
    try {
      const configRepoUrl = String.fromEnvironment(
        'CONFIG_REPO_URL',
        defaultValue:
            'https://raw.githubusercontent.com/terra-femme/xene_dart/main/packages/xene_app/lib/config.json',
      );
      final response = await _dio.get<String>(
        configRepoUrl,
        options: Options(connectTimeout: const Duration(seconds: 5)),
      );

      if (response.statusCode == 200 && response.data != null) {
        final config = jsonDecode(response.data!) as Map<String, dynamic>;
        // Cache the config.
        await _cacheConfig(config);
        return config;
      }
    } catch (e) {
      print('[ConfigNotifier] Error fetching config: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getCachedConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        return jsonDecode(cached) as Map<String, dynamic>;
      }
    } catch (e) {
      print('[ConfigNotifier] Error reading cache: $e');
    }
    return null;
  }

  Future<void> _cacheConfig(Map<String, dynamic> config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final withTimestamp = {
        ...config,
        '_cachedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_cacheKey, jsonEncode(withTimestamp));
    } catch (e) {
      print('[ConfigNotifier] Error caching config: $e');
    }
  }

  AppConfig _sanitizeProductionConfig(AppConfig config) {
    final backendUrl = _isLocalUrl(config.backendUrl)
        ? kProductionBackendUrl
        : config.backendUrl;
    final authRedirectUrl = _isLocalUrl(config.authRedirectUrl)
        ? kProductionBackendUrl
        : config.authRedirectUrl;
    if (backendUrl == config.backendUrl &&
        authRedirectUrl == config.authRedirectUrl) {
      return config;
    }
    return AppConfig(
      backendUrl: backendUrl,
      authRedirectUrl: authRedirectUrl,
      configRepoUrl: config.configRepoUrl,
      dioTimeoutConnectSeconds: config.dioTimeoutConnectSeconds,
      dioTimeoutReceiveSeconds: config.dioTimeoutReceiveSeconds,
      capacityCheckTimeoutConnectSeconds:
          config.capacityCheckTimeoutConnectSeconds,
      capacityCheckTimeoutReceiveSeconds:
          config.capacityCheckTimeoutReceiveSeconds,
      monitorTimeoutConnectSeconds: config.monitorTimeoutConnectSeconds,
      monitorTimeoutReceiveSeconds: config.monitorTimeoutReceiveSeconds,
      monitorPollIntervalSeconds: config.monitorPollIntervalSeconds,
      presetSourcesTimeoutMinutes: config.presetSourcesTimeoutMinutes,
      feedWindowLimit: config.feedWindowLimit,
      feedArchivePageLimit: config.feedArchivePageLimit,
      feedFullArchivePageLimit: config.feedFullArchivePageLimit,
      cacheRecentFastMinutes: config.cacheRecentFastMinutes,
      cacheRecentBcMinutes: config.cacheRecentBcMinutes,
      cacheArchiveMinutes: config.cacheArchiveMinutes,
      userCap: config.userCap,
      trackAnalysisMaxAttempts: config.trackAnalysisMaxAttempts,
      soundcloudConnectionPollIntervalSeconds:
          config.soundcloudConnectionPollIntervalSeconds,
      soundcloudConnectionPollTimeoutMinutes:
          config.soundcloudConnectionPollTimeoutMinutes,
      searchDebounceMilliseconds: config.searchDebounceMilliseconds,
      trackAnalysisPollIntervalSeconds: config.trackAnalysisPollIntervalSeconds,
      feedFetchDelayMilliseconds: config.feedFetchDelayMilliseconds,
    );
  }
}

/// Centralized app configuration provider.
/// Loads config from GitHub (cached), falls back to local cache,
/// and supports environment variable overrides.
///
/// Usage:
///   final config = ref.watch(appConfigProvider);
///   config.whenData((conf) => print(conf.backendUrl));
final appConfigProvider = AsyncNotifierProvider<ConfigNotifier, AppConfig>(
  ConfigNotifier.new,
);
