import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';

/// Wire-level guard for the empty-digest path of routes/inbox/daily.dart.
///
/// That route used `Response.json(statusCode: 204, body: {...})`, which really
/// does put a body on the wire — `content-length: 52` followed by 52 bytes of
/// JSON. RFC 9110 §15.3.5 forbids a body on a 204, and browsers enforce it: the
/// request fails at the network layer and reaches Dio as a connectionError with
/// no status code, so the client's `statusCode == 204` branch never runs.
///
/// These assertions read raw bytes off a socket on purpose. curl reports this
/// response as a clean `204 / size 0` because it stops reading the body once it
/// sees the status — which is exactly why the defect survived server-side
/// probing and only ever showed up in the browser.
void main() {
  group('inbox/daily 204 framing', () {
    late HttpServer server;

    Future<String> rawGet(int port) async {
      final socket = await Socket.connect('127.0.0.1', port);
      socket.write(
        'GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n',
      );
      await socket.flush();
      final raw = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      await socket.close();
      return raw;
    }

    /// Content-Length as advertised in the response head, or null if absent.
    int? declaredLength(String raw) {
      final match = RegExp(
        r'content-length:\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(raw);
      return match == null ? null : int.parse(match.group(1)!);
    }

    /// Bytes actually present after the header terminator.
    int actualBodyBytes(String raw) {
      final split = raw.indexOf('\r\n\r\n');
      return split == -1 ? 0 : raw.length - split - 4;
    }

    tearDown(() async => server.close(force: true));

    test(
      'bodyless 204 sends no body — this is what the route must do',
      () async {
        server = await serve(
          (_) => Response(statusCode: HttpStatus.noContent),
          '127.0.0.1',
          0,
        );

        final raw = await rawGet(server.port);

        expect(raw, startsWith('HTTP/1.1 204'));
        expect(
          actualBodyBytes(raw),
          isZero,
          reason:
              'a 204 must not carry a body (RFC 9110 §15.3.5) — if this '
              'fails, inbox/daily.dart has regressed to Response.json and the '
              'daily digest will break in browsers whenever it is empty',
        );
        expect(declaredLength(raw) ?? 0, isZero);

        print('✓ bodyless 204: declared=${declaredLength(raw) ?? 0} actual=0');
      },
    );

    test('Response.json on a 204 puts a real body on the wire', () async {
      // Documents WHY the route cannot use Response.json here. If a future
      // dart_frog release special-cases 204, this test fails and the comment
      // in routes/inbox/daily.dart can be relaxed.
      server = await serve(
        (_) => Response.json(
          statusCode: HttpStatus.noContent,
          body: {'message': 'No tracks dropped in the last 24 hours'},
        ),
        '127.0.0.1',
        0,
      );

      final raw = await rawGet(server.port);
      final declared = declaredLength(raw) ?? 0;
      final actual = actualBodyBytes(raw);

      expect(raw, startsWith('HTTP/1.1 204'));
      expect(
        actual,
        greaterThan(0),
        reason:
            'Response.json encodes a body regardless of status, and dart:io '
            'transmits it',
      );
      expect(
        declared,
        equals(actual),
        reason:
            'the body is fully framed and delivered — this is a spec '
            'violation, not a truncation',
      );
      expect(raw, contains('No tracks dropped in the last 24 hours'));

      print(
        '✓ Response.json 204 defect reproduced: declared=$declared '
        'actual=$actual bytes of body on a 204 — browser-visible',
      );
    });
  });
}
