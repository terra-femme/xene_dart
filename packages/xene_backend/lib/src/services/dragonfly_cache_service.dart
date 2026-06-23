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

  factory DragonflyCache() {
    _instance ??= DragonflyCache._();
    return _instance!;
  }

  DragonflyCache._();

  /// Initialize connection to DragonflyDB. Call once at app startup.
  Future<bool> init({bool failOpen = true}) async {
    final urlStr = Platform.environment['DRAGONFLY_URL'] ?? 'redis://localhost:6379';

    try {
      final uri = Uri.parse(urlStr);
      _host = uri.host.isEmpty ? 'localhost' : uri.host;
      _port = uri.port == 0 ? 6379 : uri.port;

      _logger.info('[dragonfly_cache] Testing connection to $_host:$_port');

      final pingResult = await _sendCommand(['PING']);
      if (pingResult == 'PONG') {
        _logger.info('[dragonfly_cache] Connected successfully ✓');
        _connected = true;
        return true;
      }
      throw 'PING did not return PONG: $pingResult';
    } catch (e) {
      _logger.warning('[dragonfly_cache] Connection failed: $e');
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
        _logger.fine('[dragonfly_cache] GET $key (hit)');
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
      return (result as int) > 0;
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

  /// Send a command to Redis using RESP protocol.
  Future<dynamic> _sendCommand(List<String> command, {Duration timeout = const Duration(seconds: 5)}) async {
    late Socket socket;
    try {
      socket = await Socket.connect(_host, _port, timeout: timeout);

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

      subscription = socket.timeout(timeout).listen(
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

      return completer.future;
    } catch (e) {
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
      if (buffer[i] == 13 && buffer[i + 1] == 10) { // \r\n
        return i;
      }
    }
    return -1;
  }
}
