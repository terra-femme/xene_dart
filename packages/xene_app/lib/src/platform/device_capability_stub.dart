/// Non-web (native) device-capability hint.
///
/// Browsers expose the Device Memory API; native doesn't, so we approximate
/// "low-end" with the logical core count ([Platform.numberOfProcessors]).
/// Budget Android tablets (e.g. Amazon Fire, ~4 cores) and old phones report
/// ≤4; current mid/flagship phones report 6–8, and iOS devices are ≥6 even at
/// the base — so capable devices correctly stay FULL. A >4 result returns
/// `null` ("unknown") so the runtime jank watcher still has the final say.
library;

import 'dart:io';

/// Returns a coarse "is this a low-end device?" hint:
/// - `true`  → few cores → start in the lite feed (cheap-to-build cards)
/// - `null`  → can't decide from cores alone; defer to the runtime watcher
bool? webLowEndHint() {
  final cores = Platform.numberOfProcessors;
  if (cores > 0 && cores <= 4) return true;
  return null;
}
