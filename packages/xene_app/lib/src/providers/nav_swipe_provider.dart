/// Ordered list of the primary routes that participate in horizontal swipe
/// navigation. The index of each entry is the corresponding
/// `StatefulShellBranch` index in the router (main.dart), so header taps and
/// the shell swipe gesture map a path/index straight onto
/// `StatefulNavigationShell.goBranch(index)`.
///
/// Must stay in sync — and in order — with the `branches:` list in main.dart.
///
/// Note: the old `navIndexProvider` / `navGoingForward` / `skipNextTransition`
/// globals were retired in the StatefulShellRoute migration. The shell's
/// `currentIndex` is now the single source of truth for the active page and the
/// slide direction.
const kSwipeNavRoutes = [
  '/',
  '/articles',
  '/following',
  '/game',
  '/channels',
  '/profile',
  '/about',
];
