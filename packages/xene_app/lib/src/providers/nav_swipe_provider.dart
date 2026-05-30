import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ordered list of routes that participate in horizontal swipe navigation.
/// Must stay in sync with GoRouter route definitions in main.dart.
const kSwipeNavRoutes = [
  '/',
  '/articles',
  '/following',
  '/game',
  '/channels',
  '/profile',
  '/about',
];

/// Index of the currently active page in [kSwipeNavRoutes].
/// Updated by header taps and swipe commits so swipe always knows its position
/// even after non-linear tap navigation.
final navIndexProvider = StateProvider<int>((ref) => 0);

/// Direction captured at the moment a navigation is triggered.
/// `true` = forward (new page enters from the right).
/// Read inside [CustomTransitionPage]'s transitionsBuilder closure, which
/// captures the value at page-build time — so each page records its own direction.
bool navGoingForward = true;

/// When `true`, the next [CustomTransitionPage] transition is skipped (zero
/// duration). Set before swipe-commit navigations so the entrance animation
/// doesn't double-up with the manual slide-out animation.
bool skipNextTransition = false;
