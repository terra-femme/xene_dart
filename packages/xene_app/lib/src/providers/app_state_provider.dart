import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controls the startup reveal sequence.
/// 0 = loading overlay fully visible
/// 1 = header fading in
/// 2 = sidebar fading in
/// 3 = feed content fading in
/// 4 = draggable sheet fading in
/// 5 = fully revealed, overlay removed
final appRevealProvider = StateProvider<int>((ref) => 0);
