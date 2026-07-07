/// Web implementation of the device-capability hint.
///
/// Reads the browser's Device Memory API (`navigator.deviceMemory`, in GB,
/// quantized to 0.25/0.5/1/2/4/8) and `navigator.hardwareConcurrency` (logical
/// cores). These let us cleanly separate a weak Android tablet from iOS and
/// capable Android *without* hardcoding platform:
/// - iOS Safari / Firefox don't implement deviceMemory → returns `null`
///   ("unknown"), so iOS is treated as capable unless the runtime watcher
///   later demotes it.
/// - Low-RAM / low-core Android reports small numbers → `true` (lite).
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

// Typed view over `navigator` so we can read deviceMemory regardless of whether
// the installed package:web version surfaces it. An undefined property comes
// back as null for a nullable external getter.
extension type _CapabilityNavigator(JSObject _) implements JSObject {
  external JSNumber? get deviceMemory;
  external int get hardwareConcurrency;
}

bool? webLowEndHint() {
  final nav = _CapabilityNavigator(web.window.navigator as JSObject);

  final memGb = nav.deviceMemory?.toDartDouble;
  final cores = nav.hardwareConcurrency;

  if (memGb == null) {
    // deviceMemory unsupported (iOS Safari, Firefox, ...). Only call it low-end
    // if cores are clearly minimal; otherwise defer to the runtime watcher.
    if (cores > 0 && cores <= 2) return true;
    return null;
  }

  // 4GB-or-less, or 4-or-fewer logical cores → treat as low-end. Most current
  // flagships report 8 (the spec cap); budget/older Android tablets report 2–4.
  return memGb <= 4 || cores <= 4;
}
