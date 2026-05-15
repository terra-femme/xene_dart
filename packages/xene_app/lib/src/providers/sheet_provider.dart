import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ELI5: This keeps track of where the "Sliding Sheet" is on the screen.
/// Every widget can check this to know how high the sheet has been pulled up.
final sheetProvider = Provider<DraggableScrollableController>((ref) {
  final controller = DraggableScrollableController();
  ref.onDispose(() => controller.dispose());
  return controller;
});
