import 'package:test/test.dart';
import 'package:xene_backend/src/services/dragonfly_cache_service.dart';

void main() {
  // Fail-open behaviour needs no server, so it stays outside the tagged group
  // and runs on every `dart test`. This matters more than the rest of this file
  // right now: with the DragonflyDB container app retired, the short-circuit is
  // the only path production actually takes, and it was previously untested
  // because the shared setUp below demanded a live connection first.
  group('DragonflyCache fail-open (no server required)', () {
    test('operations return safe defaults when never connected', () async {
      // A fresh instance is disconnected by default — `_connected` starts false
      // and every operation short-circuits on it, so this needs no init().
      final cache = DragonflyCache();

      expect(cache.isConnected, false);
      expect(await cache.set('test:key', 'value'), false);
      expect(await cache.get('test:key'), null);
      expect(await cache.exists('test:key'), false);
      expect(await cache.delete('test:key'), false);
      expect(await cache.incr('test:key'), null);
    });

    test('operations return safe defaults after close()', () async {
      final cache = DragonflyCache();
      // failOpen: true — init against an absent server must not throw.
      await cache.init(failOpen: true);
      await cache.close();

      expect(cache.isConnected, false);
      expect(await cache.set('test:key', 'value'), false);
      expect(await cache.get('test:key'), null);
      expect(await cache.exists('test:key'), false);
      expect(await cache.delete('test:key'), false);
      expect(await cache.incr('test:key'), null);
    });
  });

  // Everything below talks to a real DragonflyDB on localhost:6379. Skipped by
  // default via the `dragonfly` tag in dart_test.yaml; see that file to run them.
  group('DragonflyCache', tags: 'dragonfly', () {
    late DragonflyCache cache;

    setUp(() async {
      cache = DragonflyCache();
      // Note: DragonflyDB must be running on localhost:6379
      // docker compose up -d dragonfly
      final connected = await cache.init(failOpen: false);
      expect(connected, true, reason: 'DragonflyDB must be running');
    });

    tearDown(() async {
      await cache.close();
    });

    test('SET and GET a string value', () async {
      final result = await cache.set('test:key', 'hello world');
      expect(result, true);

      final value = await cache.get('test:key');
      expect(value, 'hello world');
    });

    test('SET with TTL and expiry', () async {
      final result = await cache.set(
        'test:ttl',
        'expires soon',
        expirySeconds: 2,
      );
      expect(result, true);

      var value = await cache.get('test:ttl');
      expect(value, 'expires soon');

      // Wait for expiry
      await Future.delayed(Duration(seconds: 3));
      value = await cache.get('test:ttl');
      expect(value, null);
    });

    test('EXISTS checks key presence', () async {
      await cache.set('test:exists', 'value');

      var exists = await cache.exists('test:exists');
      expect(exists, true);

      await cache.delete('test:exists');
      exists = await cache.exists('test:exists');
      expect(exists, false);
    });

    test('DELETE removes a key', () async {
      await cache.set('test:delete', 'value');

      var deleted = await cache.delete('test:delete');
      expect(deleted, true);

      deleted = await cache.delete('test:delete'); // already deleted
      expect(deleted, false);

      final value = await cache.get('test:delete');
      expect(value, null);
    });

    test('INCR increments counter atomically', () async {
      await cache.delete('test:counter'); // clean slate

      var count = await cache.incr('test:counter');
      expect(count, 1);

      count = await cache.incr('test:counter');
      expect(count, 2);

      count = await cache.incr('test:counter');
      expect(count, 3);

      final value = await cache.get('test:counter');
      expect(value, '3');
    });

    test('EXPIRE extends TTL on existing key', () async {
      await cache.set('test:renew', 'value', expirySeconds: 1);

      var renewed = await cache.expire('test:renew', 10);
      expect(renewed, true);

      // Wait original TTL + some
      await Future.delayed(Duration(seconds: 2));

      // Should still exist (extended TTL)
      final value = await cache.get('test:renew');
      expect(value, 'value');
    });

    test('Distributed coalescing scenario', () async {
      // Simulate multiple requests trying to fetch same key
      final key = 'test:feed_inflight:soundcloud:artist1';

      // First request sets marker
      var result = await cache.set(key, 'fetching', expirySeconds: 10);
      expect(result, true);

      // Second request sees marker
      var exists = await cache.exists(key);
      expect(exists, true);

      // Third request also sees marker
      exists = await cache.exists(key);
      expect(exists, true);

      // Cleanup (first request done)
      result = await cache.delete(key);
      expect(result, true);

      // Marker gone
      exists = await cache.exists(key);
      expect(exists, false);
    });

    test('Operations gracefully fail when disconnected', () async {
      // Temporarily close connection
      await cache.close();

      // Operations should return safely without throwing
      var result = await cache.set('test:key', 'value');
      expect(result, false);

      var value = await cache.get('test:key');
      expect(value, null);

      var exists = await cache.exists('test:key');
      expect(exists, false);

      var deleted = await cache.delete('test:key');
      expect(deleted, false);

      var count = await cache.incr('test:key');
      expect(count, null);

      // Reconnect for teardown (setUp runs before tearDown)
      await cache.init(failOpen: true);
    });
  });
}
