import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:supabase/supabase.dart' hide HttpMethod;

final _logger = Logger('auth.email_exists');

/// GET /auth/email-exists?email=test@example.com
/// Public endpoint (no auth required) — checks if an email exists in auth.users
/// Used by signup flow to determine if user is returning or new.
/// Returns: { exists: bool }
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final email = context.request.uri.queryParameters['email']?.trim();
  if (email == null || email.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'email parameter required'},
    );
  }

  try {
    final supabase = context.read<SupabaseClient>();

    // Use RPC function to check if email exists
    final exists =
        await supabase.rpc('check_user_exists', params: {'user_email': email})
            as bool? ??
        false;

    _logger.info('[email_exists] email=$email exists=$exists');

    return Response.json(body: {'exists': exists});
  } catch (e) {
    _logger.warning('[email_exists] Error checking email: $e');
    return Response.json(
      statusCode: 500,
      body: {'error': 'Could not check email', 'exists': false},
    );
  }
}
