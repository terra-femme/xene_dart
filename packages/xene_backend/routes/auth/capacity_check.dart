import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:supabase/supabase.dart';
import 'package:xene_backend/src/services/capacity_service.dart';

final _logger = Logger('auth.capacity_check');

/// GET /auth/capacity-check?email=user@example.com
/// Public endpoint (no auth required) — returns signup eligibility.
/// - Existing users can always sign in (emailExists=true)
/// - New users blocked if at capacity
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final email = context.request.uri.queryParameters['email']?.trim();
  final capacity = context.read<CapacityService>();
  final supabase = context.read<SupabaseClient>();

  try {
    final status = await capacity.getStatus();
    final signupsAllowed = status.userCount < 2000;

    // Check if email exists in auth.users (means returning user)
    bool emailExists = false;
    if (email != null && email.isNotEmpty) {
      try {
        final result = await supabase.rpc(
          'check_user_exists',
          params: {'user_email': email},
        );
        emailExists = result as bool? ?? false;
      } catch (e) {
        _logger.warning('[capacity_check] Could not check email existence: $e');
        // Default to allowing if we can't check (better to be generous)
        emailExists = false;
      }
    }

    // Allow if: signups open OR email exists (returning user)
    final canSignUp = signupsAllowed || emailExists;

    _logger.info(
      '[capacity_check] email=$email exists=$emailExists users=${status.userCount}/2000 canSignUp=$canSignUp',
    );

    return Response.json(
      body: {
        'signups_allowed': signupsAllowed,
        'email_exists': emailExists,
        'can_sign_up': canSignUp,
        'user_count': status.userCount,
        'user_cap': 2000,
        'user_cap_percent': status.userCapPercent,
        'message': canSignUp
            ? (emailExists ? 'Welcome back' : 'Signups are open')
            : 'Signups temporarily disabled — user capacity reached',
      },
    );
  } catch (e) {
    _logger.severe('[capacity_check] Error: $e');
    // Fail open - allow signup if we can't check
    return Response.json(
      statusCode: 500,
      body: {
        'error': 'Could not check capacity',
        'signups_allowed': true,
        'email_exists': false,
        'can_sign_up': true,
      },
    );
  }
}
