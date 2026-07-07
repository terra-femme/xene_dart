import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config_provider.dart';

class CapacityCheckResponse {
  const CapacityCheckResponse({
    required this.signupsAllowed,
    required this.userCount,
    required this.userCap,
    required this.userCapPercent,
    required this.message,
    required this.canSignUp,
    required this.emailExists,
  });

  final bool signupsAllowed;
  final int userCount;
  final int userCap;
  final double userCapPercent;
  final String message;
  final bool canSignUp;
  final bool emailExists;

  factory CapacityCheckResponse.fromJson(Map<String, dynamic> json) =>
      CapacityCheckResponse(
        signupsAllowed: json['signups_allowed'] as bool? ?? true,
        userCount: json['user_count'] as int? ?? 0,
        userCap: json['user_cap'] as int? ?? 2000,
        userCapPercent: json['user_cap_percent'] as double? ?? 0.0,
        message: json['message'] as String? ?? '',
        canSignUp: json['can_sign_up'] as bool? ?? true,
        emailExists: json['email_exists'] as bool? ?? false,
      );
}

/// Checks if signups are currently allowed (capacity not full).
/// No email parameter - returns general capacity status.
final capacityCheckProvider = FutureProvider<CapacityCheckResponse>((
  ref,
) async {
  final configAsync = ref.watch(appConfigProvider);

  final config = configAsync.whenData((c) => c).asData?.value;
  if (config == null) {
    throw Exception('Failed to load app configuration');
  }

  final dio = Dio(
    BaseOptions(
      baseUrl: config.backendUrl,
      connectTimeout: Duration(
        seconds: config.capacityCheckTimeoutConnectSeconds,
      ),
      receiveTimeout: Duration(
        seconds: config.capacityCheckTimeoutReceiveSeconds,
      ),
    ),
  );

  try {
    final res = await dio.get<Map<String, dynamic>>('/auth/capacity-check');
    if (res.data != null) {
      return CapacityCheckResponse.fromJson(res.data!);
    }
  } catch (e) {
    // Fail open: a failing capacity check must never block sign-in. Log and
    // fall through to the permissive default below (the backend handler itself
    // fails open too). The cap still enforces when the endpoint responds.
    debugPrint('[capacityCheck] check failed, failing open: $e');
  }

  return CapacityCheckResponse(
    signupsAllowed: true,
    userCount: 0,
    userCap: config.userCap,
    userCapPercent: 0.0,
    message: 'Unable to check capacity',
    canSignUp: true,
    emailExists: false,
  );
});

/// Checks signup eligibility for a specific email.
/// Existing users can always sign up (emailExists=true).
/// New users blocked if at capacity.
final checkEmailSignupProvider =
    FutureProvider.family<CapacityCheckResponse, String?>((ref, email) async {
      if (email == null || email.isEmpty) {
        return ref.watch(capacityCheckProvider.future);
      }

      final configAsync = ref.watch(appConfigProvider);

      final config = configAsync.whenData((c) => c).asData?.value;
      if (config == null) {
        throw Exception('Failed to load app configuration');
      }

      final dio = Dio(
        BaseOptions(
          baseUrl: config.backendUrl,
          connectTimeout: Duration(
            seconds: config.capacityCheckTimeoutConnectSeconds,
          ),
          receiveTimeout: Duration(
            seconds: config.capacityCheckTimeoutReceiveSeconds,
          ),
        ),
      );

      try {
        final res = await dio.get<Map<String, dynamic>>(
          '/auth/capacity-check',
          queryParameters: {'email': email.trim()},
        );
        if (res.data != null) {
          return CapacityCheckResponse.fromJson(res.data!);
        }
      } catch (e) {
        // Fail open: a failing capacity check must never block sign-in. Log and
        // fall through to the permissive default below. The cap still enforces
        // when the endpoint responds normally.
        debugPrint('[checkEmailSignup] check failed, failing open: $e');
      }

      return CapacityCheckResponse(
        signupsAllowed: true,
        userCount: 0,
        userCap: config.userCap,
        userCapPercent: 0.0,
        message: 'Unable to check eligibility',
        canSignUp: true,
        emailExists: false,
      );
    });
