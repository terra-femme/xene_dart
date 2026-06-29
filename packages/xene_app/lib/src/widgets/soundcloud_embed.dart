// Platform facade for the SoundCloud embed:
//   web    → real <iframe> via package:web         (soundcloud_embed_web.dart)
//   native → SC Widget API HTML inside a WebView    (soundcloud_embed_native.dart)
//   other  → placeholder                            (soundcloud_embed_stub.dart)
// dart.library.html is web-only; dart.library.io is true on Android/iOS/desktop.
// First matching condition wins, so web is checked before native.
export 'soundcloud_embed_stub.dart'
    if (dart.library.html) 'soundcloud_embed_web.dart'
    if (dart.library.io) 'soundcloud_embed_native.dart';
