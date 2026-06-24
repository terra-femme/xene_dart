import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';

final _logger = Logger('dragonfly_cache');

/// DragonflyDB-backed distributed cache service (Redis-compatible).
/// Replaces in-process caches across multiple replicas with a single source of truth.
class DragonflyCache {
  static DragonflyCache? _instance;

  late String _host;
  late int _port;
  bool _connected = false;

  // Metrics tracking
  int _getHits = 0;
  int _getMisses = 0;
  int _setOperations = 0;
  int _deleteOperations = 0;
  int _totalLatencyMs = 0;
  int _operationCount = 0;
  DateTime _metricsStartTime = DateTime.now();

  factory DragonflyCache() {
    _instance ??= DragonflyCache._();
    return _instance!;
  }

  DragonflyCache._();

  /// Initialize connection to DragonflyDB. Call once at app startup.
  Future<bool> init({bool failOpen = true}) async {
    final urlStr =
        Platform.environment['DRAGONFLY_URL'] ?? 'redis://localhost:6379';

    try {
      final uri = Uri.parse(urlStr);
      _host = uri.host.isEmpty ? 'localhost' : uri.host;
      _port = uri.port == 0 ? 6379 : uri.port;

      print('[DRAGONFLY_CACHE] INIT: DRAGONFLY_URL env = $urlStr');
      print('[DRAGONFLY_CACHE] INIT: Parsed host=$_host, port=$_port');
      _logger.info('[dragonfly_cache] Testing connection to $_host:$_port');

      final pingResult = await _sendCommand(['PING']);
      print('[DRAGONFLY_CACHE] INIT: PING response = $pingResult');
      if (pingResult == 'PONG') {
        print('[DRAGONFLY_CACHE] INIT: Connection SUCCESS ✓');
        _logger.info('[dragonfly_cache] Connected successfully ✓');
        _connected = true;
        return true;
      }
      throw 'PING did not return PONG: $pingResult';
    } catch (e, stack) {
      print('[DRAGONFLY_CACHE] INIT: Connection FAILED: $e');
      print('[DRAGONFLY_CACHE] INIT: Stack trace: $stack');
      _logger.warning('[dragonfly_cache] Connection failed: $e', e, stack);
      _connected = false;
      if (!failOpen) rethrow;
      return false;
    }
  }

  /// Graceful shutdown.
  Future<void> close() async {
    _connected = false;
    _logger.info('[dragonfly_cache] Connection closed');
  }

  /// Store a value with optional TTL.
  Future<bool> set(String key, String value, {int? expirySeconds}) async {
    if (!_connected) return false;
    try {
      final cmd = expirySeconds != null
          ? ['SETEX', key, expirySeconds.toString(), value]
          : ['SET', key, value];
      final result = await _sendCommand(cmd);
      if (result == 'OK') {
        _setOperations++;
        _logger.fine('[dragonfly_cache] SET $key');
        return true;
      }
      return false;
    } catch (e) {
      _logger.warning('[dragonfly_cache] SET $key failed: $e');
      _connected = false;
      return false;
    }
  }

  /// Retrieve a value.
  Future<String?> get(String key) async {
    if (!_connected) return null;
    try {
      final value = await _sendCommand(['GET', key]) as String?;
      if (value != null) {
        _getHits++;
        _logger.fine('[dragonfly_cache] GET $key (hit)');
      } else {
        _getMisses++;
        _logger.fine('[dragonfly_cache] GET $key (miss)');
      }
      return value;
    } catch (e) {
      _logger.warning('[dragonfly_cache] GET $key failed: $e');
      _connected = false;
      return null;
    }
  }

  /// Check if key exists.
  Future<bool> exists(String key) async {
    if (!_connected) return false;
    try {
      final result = await _sendCommand(['EXISTS', key]);
      return (result as int) > 0;
    } catch (e) {
      _logger.warning('[dragonfly_cache] EXISTS $key failed: $e');
      _connected = false;
      return false;
    }
  }

  /// Delete a key.
  Future<bool> delete(String key) async {
    if (!_connected) return false;
    try {
      final result = await _sendCommand(['DEL', key]);
      if ((result as int) > 0) {
        _deleteOperations++;
        return true;
      }
      return false;
    } catch (e) {
      _logger.warning('[dragonfly_cache] DEL $key failed: $e');
      _connected = false;
      return false;
    }
  }

  /// Set expiry on existing key.
  Future<bool> expire(String key, int seconds) async {
    if (!_connected) return false;
    try {
      final result = await _sendCommand(['EXPIRE', key, seconds.toString()]);
      return (result as int) > 0;
    } catch (e) {
      _logger.warning('[dragonfly_cache] EXPIRE $key failed: $e');
      _connected = false;
      return false;
    }
  }

  /// Increment counter.
  Future<int?> incr(String key) async {
    if (!_connected) return null;
    try {
      final result = await _sendCommand(['INCR', key]);
      _logger.fine('[dragonfly_cache] INCR $key -> $result');
      return result as int;
    } catch (e) {
      _logger.warning('[dragonfly_cache] INCR $key failed: $e');
      _connected = false;
      return null;
    }
  }

  /// Check if connected.
  bool get isConnected => _connected;

  /// Get cache metrics.
  Future<Map<String, dynamic>> getMetrics() async {
    double hitRatio = 0.0;
    final totalGets = _getHits + _getMisses;
    if (totalGets > 0) {
      hitRatio =
          (_getHits / totalGets * 100)
                  .toStringAsFixed(2)
                  .split('.')
                  .join('.')
                  .replaceFirst('.', '.')
              as dynamic;
      hitRatio = double.parse((_getHits / totalGets * 100).toStringAsFixed(2));
    }

    double avgLatencyMs = 0.0;
    if (_operationCount > 0) {
      avgLatencyMs = double.parse(
        (_totalLatencyMs / _operationCount).toStringAsFixed(2),
      );
    }

    // Fetch memory info from Redis
    int usedMemory = 0;
    if (_connected) {
      try {
        final infoStr = await _sendCommand(['INFO', 'memory']) as String?;
        if (infoStr != null) {
          final lines = infoStr.split('\r\n');
          for (final line in lines) {
            if (line.startsWith('used_memory:')) {
              final parts = line.split(':');
              if (parts.length > 1) {
                usedMemory = int.tryParse(parts[1]) ?? 0;
              }
              break;
            }
          }
        }
      } catch (e) {
        _logger.warning('[dragonfly_cache] Failed to fetch INFO: $e');
      }
    }

    final uptime = DateTime.now().difference(_metricsStartTime);

    return {
      'connected': _connected,
      'uptime_seconds': uptime.inSeconds,
      'total_operations': _operationCount,
      'get_hits': _getHits,
      'get_misses': _getMisses,
      'hit_ratio_percent': hitRatio,
      'set_operations': _setOperations,
      'delete_operations': _deleteOperations,
      'average_latency_ms': avgLatencyMs,
      'total_latency_ms': _totalLatencyMs,
      'memory_used_bytes': usedMemory,
      'memory_used_mb': (usedMemory / (1024 * 1024)).toStringAsFixed(2),
    };
  }

  /// Send a command to Redis using RESP protocol.
  Future<dynamic> _sendCommand(
    List<String> command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    late Socket socket;
    final startTime = DateTime.now();
    try {
      print('[DRAGONFLY_CACHE] _sendCommand: Attempting Socket.connect($_host:$_port) with ${timeout.inSeconds}s timeout');
      socket = await Socket.connect(_host, _port, timeout: timeout);
      print('[DRAGONFLY_CACHE] _sendCommand: Socket.connect() SUCCESS');

      // Build RESP request
      final buffer = StringBuffer();
      buffer.write('*${command.length}\r\n');
      for (final arg in command) {
        buffer.write('\$${arg.length}\r\n$arg\r\n');
      }

      final request = buffer.toString();
      socket.write(request);
      await socket.flush();

      // Read all response data
      final responseData = <int>[];
      final completer = Completer<dynamic>();
      late StreamSubscription subscription;

      subscription = socket
          .timeout(timeout)
          .listen(
            (data) {
              responseData.addAll(data);
              // Try to parse as we go
              try {
                final parsed = _parseResp(responseData);
                if (parsed != null) {
                  subscription.cancel();
                  socket.destroy();
                  completer.complete(parsed['value']);
                }
              } catch (_) {
                // Keep reading
              }
            },
            onError: (e) {
              subscription.cancel();
              socket.destroy();
              completer.completeError(e);
            },
            onDone: () {
              subscription.cancel();
              socket.destroy();
              if (!completer.isCompleted) {
                try {
                  final parsed = _parseResp(responseData);
                  if (parsed != null) {
                    completer.complete(parsed['value']);
                  } else {
                    completer.completeError('Incomplete RESP response');
                  }
                } catch (e) {
                  completer.completeError(e);
                }
              }
            },
            cancelOnError: true,
          );

      final result = await completer.future;
      final latencyMs = DateTime.now().difference(startTime).inMilliseconds;
      _totalLatencyMs += latencyMs;
      _operationCount++;
      print('[DRAGONFLY_CACHE] _sendCommand: Command ${command.join(" ")} succeeded in ${latencyMs}ms');
      return result;
    } catch (e, stack) {
      print('[DRAGONFLY_CACHE] _sendCommand: FAILED with error: $e');
      print('[DRAGONFLY_CACHE] _sendCommand: Stack: $stack');
      try {
        socket.destroy();
      } catch (_) {}
      rethrow;
    }
  }

  /// Parse RESP response from buffer. Returns {value, bytesConsumed} or null if incomplete.
  Map<String, dynamic>? _parseResp(List<int> buffer) {
    if (buffer.isEmpty) return null;

    int pos = 0;
    final type = String.fromCharCode(buffer[pos++]);

    switch (type) {
      case '+': // Simple String
        final endPos = _findCrLf(buffer, pos);
        if (endPos == -1) return null;
        final line = utf8.decode(buffer.sublist(pos, endPos));
        return {'value': line, 'bytesConsumed': endPos + 2};

      case '-': // Error
        final endPos = _findCrLf(buffer, pos);
        if (endPos == -1) return null;
        final line = utf8.decode(buffer.sublist(pos, endPos));
        throw 'Redis error: $line';

      case ':': // Integer
        final endPos = _findCrLf(buffer, pos);
        if (endPos == -1) return null;
        final line = utf8.decode(buffer.sublist(pos, endPos));
        return {'value': int.parse(line), 'bytesConsumed': endPos + 2};

      case '\$': // Bulk String
        final lineEnd = _findCrLf(buffer, pos);
        if (lineEnd == -1) return null;
        final lenStr = utf8.decode(buffer.sublist(pos, lineEnd));
        final len = int.parse(lenStr);
        if (len == -1) {
          return {'value': null, 'bytesConsumed': lineEnd + 2};
        }
        final dataStart = lineEnd + 2;
        final dataEnd = dataStart + len;
        if (buffer.length < dataEnd + 2) return null; // Need \r\n after data
        final data = utf8.decode(buffer.sublist(dataStart, dataEnd));
        return {'value': data, 'bytesConsumed': dataEnd + 2};

      case '*': // Array (simplified - assumes no nested arrays for now)
        final lineEnd = _findCrLf(buffer, pos);
        if (lineEnd == -1) return null;
        final countStr = utf8.decode(buffer.sublist(pos, lineEnd));
        final count = int.parse(countStr);
        if (count == -1) {
          return {'value': null, 'bytesConsumed': lineEnd + 2};
        }
        // For arrays, just read the raw response and return
        // This is a limitation but works for simple cases
        return null; // Don't parse arrays for now

      default:
        throw 'Unknown RESP type: $type';
    }
  }

  /// Find \r\n in buffer starting at position.
  int _findCrLf(List<int> buffer, int start) {
    for (int i = start; i < buffer.length - 1; i++) {
      if (buffer[i] == 13 && buffer[i + 1] == 10) {
        // \r\n
        return i;
      }
    }
    return -1;
  }
}
