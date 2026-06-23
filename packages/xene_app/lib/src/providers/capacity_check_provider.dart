import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8080',
);

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
  final dio = Dio(
    BaseOptions(
      baseUrl: _kBackendUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  try {
    final res = await dio.get<Map<String, dynamic>>('/auth/capacity-check');
    if (res.data != null) {
      return CapacityCheckResponse.fromJson(res.data!);
    }
  } catch (e) {
    throw Exception('Failed to check signup capacity: $e');
  }

  return const CapacityCheckResponse(
    signupsAllowed: true,
    userCount: 0,
    userCap: 2000,
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

      final dio = Dio(
        BaseOptions(
          baseUrl: _kBackendUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 8),
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
        throw Exception('Failed to check signup eligibility: $e');
      }

      return const CapacityCheckResponse(
        signupsAllowed: true,
        userCount: 0,
        userCap: 2000,
        userCapPercent: 0.0,
        message: 'Unable to check eligibility',
        canSignUp: true,
        emailExists: false,
      );
    });
