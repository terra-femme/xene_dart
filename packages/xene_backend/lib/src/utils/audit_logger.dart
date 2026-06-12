import 'package:logging/logging.dart';
import 'package:supabase/supabase.dart';

final _logger = Logger('audit');

/// Writes one row to security_audit_log via the service-role client.
/// Fire-and-forget: failures are logged as warnings and never surface to callers.
///
/// [action]   — snake_case identifier, e.g. 'admin_poll', 'press_scout_run'
/// [userId]   — authenticated user UUID; null for cron/system-triggered actions
/// [targetId] — optional context key (preset_id, artist_id, party_id, etc.)
/// [ip]       — client IP string from extractClientIp(); null if not applicable
/// [metadata] — any extra key/value pairs relevant to the action
Future<void> logSecurityEvent(
  SupabaseClient client, {
  required String action,
  String? userId,
  String? targetId,
  String? ip,
  Map<String, dynamic>? metadata,
}) async {
  try {
    await client.from('security_audit_log').insert({
      'action': action,
      if (userId != null) 'user_id': userId,
      if (targetId != null) 'target_id': targetId,
      if (ip != null) 'ip': ip,
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
    });
    _logger.fine('[audit] $action userId=$userId targetId=$targetId');
  } catch (e) {
    _logger.warning('[audit] Failed to write security_audit_log: $e');
  }
}
