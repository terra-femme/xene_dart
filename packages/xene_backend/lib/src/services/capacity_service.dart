import 'package:logging/logging.dart';
import '../database.dart';

final _logger = Logger('CapacityService');

const _userCap = 2000;
const _storageCap = 50; // MB, Supabase free tier

class CapacityStatus {
  const CapacityStatus({
    required this.userCount,
    required this.userCapPercent,
    required this.userAlert,
    required this.storageUsedMb,
    required this.storageCapPercent,
    required this.storageAlert,
    required this.timestamp,
  });

  final int userCount;
  final double userCapPercent;
  final String? userAlert;
  final double storageUsedMb;
  final double storageCapPercent;
  final String? storageAlert;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'users': {
      'current': userCount,
      'cap': _userCap,
      'percentUsed': userCapPercent,
      'alert': userAlert,
    },
    'storage': {
      'used_mb': storageUsedMb,
      'cap_mb': _storageCap,
      'percentUsed': storageCapPercent,
      'alert': storageAlert,
    },
    'timestamp': timestamp.toUtc().toIso8601String(),
  };
}

class CapacityService {
  CapacityService(this.db);

  final DatabaseService db;

  Future<CapacityStatus> getStatus() async {
    try {
      final userCount = await _getUserCount();
      final storageUsedMb = await _estimateStorageUsage();

      final userCapPercent = (userCount / _userCap) * 100;
      final storageCapPercent = (storageUsedMb / _storageCap) * 100;

      String? userAlert;
      if (userCapPercent >= 90) {
        userAlert = 'CRITICAL';
      } else if (userCapPercent >= 80) {
        userAlert = 'WARNING';
      }

      String? storageAlert;
      if (storageCapPercent >= 90) {
        storageAlert = 'CRITICAL';
      } else if (storageCapPercent >= 80) {
        storageAlert = 'WARNING';
      }

      return CapacityStatus(
        userCount: userCount,
        userCapPercent: userCapPercent,
        userAlert: userAlert,
        storageUsedMb: storageUsedMb,
        storageCapPercent: storageCapPercent,
        storageAlert: storageAlert,
        timestamp: DateTime.now().toUtc(),
      );
    } catch (e) {
      _logger.severe('Error getting capacity status: $e');
      rethrow;
    }
  }

  Future<int> _getUserCount() async {
    try {
      final response = await db.client
          .from('profiles')
          .select('id', const QueryOptions(count: CountOption.exact));
      return response.length;
    } catch (e) {
      _logger.warning('Error querying user count: $e');
      return 0;
    }
  }

  Future<double> _estimateStorageUsage() async {
    try {
      double totalMb = 0;

      final feedItems = await _countRows('feed_items');
      totalMb += (feedItems * 0.6) / 1024;

      final follows = await _countRows('user_artist_follows');
      totalMb += (follows * 0.1) / 1024;

      final profiles = await _countRows('profiles');
      totalMb += (profiles * 2) / 1024;

      final parties = await _countRows('game_parties');
      totalMb += (parties * 1) / 1024;

      final articles = await _countRows('publication_articles');
      totalMb += (articles * 2) / 1024;

      final saved = await _countRows('user_saved_items');
      final history = await _countRows('user_listening_history');
      totalMb += ((saved + history) * 0.5) / 1024;

      final connections = await _countRows('platform_connections');
      totalMb += (connections * 1.5) / 1024;

      final auditLog = await _countRows('security_audit_log');
      totalMb += (auditLog * 0.5) / 1024;

      totalMb *= 1.1;

      _logger.info(
        '[CapacityService] Storage estimate: ${totalMb.toStringAsFixed(2)}MB '
        '(feed_items=$feedItems, follows=${follows}, profiles=${profiles})',
      );

      return totalMb;
    } catch (e) {
      _logger.warning('Error estimating storage: $e');
      return 0;
    }
  }

  Future<int> _countRows(String tableName) async {
    try {
      final response = await db.client
          .from(tableName)
          .select('id', const QueryOptions(count: CountOption.exact));
      return response.length;
    } catch (e) {
      _logger.warning('Error counting rows in $tableName: $e');
      return 0;
    }
  }
}
