import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controls the startup reveal sequence.
/// 0 = loading overlay fully visible
/// 5 = all layers pre-warmed and visible (set instantly under opaque overlay)
final appRevealProvider = StateProvider<int>((ref) => 0);

/// true once the loading overlay has fully faded and been removed from the tree.
/// Gate crawl ticker and any post-reveal animations on this provider.
final revealCompleteProvider = StateProvider<bool>((ref) => false);
