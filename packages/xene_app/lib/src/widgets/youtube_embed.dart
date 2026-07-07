// Platform facade for the YouTube embed:
//   web    → real <iframe> via package:web      (youtube_embed_web.dart)
//   native → youtube_player_flutter player       (youtube_embed_native.dart)
//   other  → placeholder                         (youtube_embed_stub.dart)
// dart.library.html is web-only; dart.library.io is true on Android/iOS/desktop.
// First matching condition wins, so web is checked before native.
export 'youtube_embed_stub.dart'
    if (dart.library.html) 'youtube_embed_web.dart'
    if (dart.library.io) 'youtube_embed_native.dart';
