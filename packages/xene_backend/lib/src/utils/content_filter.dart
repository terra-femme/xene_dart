import 'package:xene_domain/xene_domain.dart';

/// Case-insensitive substrings that trigger a block on any FeedItem.
/// Matched against artistName, title, and body.
const _blockedTerms = <String>[
  'chris brown',
  'cbreezy',
  'chris breezy',
  'c. breezy',
];

bool isContentBlocked(FeedItem item) {
  final fields = [item.artistName, item.title ?? '', item.body ?? ''];
  for (final field in fields) {
    final lower = field.toLowerCase();
    for (final term in _blockedTerms) {
      if (lower.contains(term)) return true;
    }
  }
  return false;
}
