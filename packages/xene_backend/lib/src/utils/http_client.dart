import 'dart:io';

import 'package:dio/io.dart';

/// Per-host cap on simultaneous outbound connections for the pooled, singleton
/// platform service clients.
///
/// `dart:io`'s default [HttpClient] leaves `maxConnectionsPerHost` unbounded,
/// so a burst of concurrent scrapes (e.g. a stale-cache stampede across many
/// tracked artists) can open an unlimited number of sockets to a single host.
/// On Azure App Service that drains the limited pool of SNAT ports and trips
/// upstream 429s. Capping per host forces those requests to queue onto a
/// bounded set of reused keep-alive connections instead.
///
/// This is the connection-level companion to the request-level background
/// concurrency cap in `feed_cache.dart`.
const int kMaxConnectionsPerHost = 8;

/// How long an idle pooled connection is kept alive for reuse before the OS
/// socket is closed. Long enough to be reused across the back-to-back requests
/// a single feed refresh makes; short enough not to hoard sockets when idle.
const Duration kPooledIdleTimeout = Duration(seconds: 30);

/// Builds an [IOHttpClientAdapter] backed by a keep-alive [HttpClient] whose
/// connections are pooled and capped per host ([kMaxConnectionsPerHost]).
///
/// Intended for the long-lived singleton services (SoundCloud / YouTube /
/// Bandcamp) created once in `_middleware.dart`: each holds a single bounded
/// connection pool for the life of the process, so outbound connections are
/// reused rather than re-established per request.
IOHttpClientAdapter pooledKeepAliveAdapter() => IOHttpClientAdapter(
  createHttpClient: () => HttpClient()
    ..maxConnectionsPerHost = kMaxConnectionsPerHost
    ..idleTimeout = kPooledIdleTimeout,
);
