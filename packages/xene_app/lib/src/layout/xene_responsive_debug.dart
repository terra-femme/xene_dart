import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Gated debug logging for the responsive refactor.
///
/// Enable with:
/// `--dart-define=XENE_RESPONSIVE_DEBUG=true`
///
/// Keep calls to this helper in refactored layout code instead of scattering
/// raw debugPrint statements. That gives us heavy diagnostics during the
/// responsive pass without making normal dev sessions noisy.
abstract final class XeneResponsiveDebug {
  static const bool enabled = bool.fromEnvironment(
    'XENE_RESPONSIVE_DEBUG',
    defaultValue: false,
  );

  static void log(String scope, String message) {
    if (!kDebugMode || !enabled) return;
    debugPrint('[XeneResponsive][$scope] $message');
  }

  static void constraints(String scope, BoxConstraints constraints) {
    log(
      scope,
      'constraints='
      'minW=${_fmt(constraints.minWidth)} '
      'maxW=${_fmt(constraints.maxWidth)} '
      'minH=${_fmt(constraints.minHeight)} '
      'maxH=${_fmt(constraints.maxHeight)}',
    );
  }

  static void mediaQuery(String scope, MediaQueryData mediaQuery) {
    log(
      scope,
      'media='
      'size=${_size(mediaQuery.size)} '
      'padding=${_insets(mediaQuery.padding)} '
      'viewInsets=${_insets(mediaQuery.viewInsets)} '
      'orientation=${mediaQuery.orientation.name} '
      'textScale=${_fmt(mediaQuery.textScaler.scale(1))}',
    );
  }

  static void value(String scope, String name, Object? value) {
    log(scope, '$name=$value');
  }

  static void values(String scope, Map<String, Object?> values) {
    if (!kDebugMode || !enabled) return;
    final entries = values.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    log(scope, entries);
  }

  static String _size(Size size) {
    return '${_fmt(size.width)}x${_fmt(size.height)}';
  }

  static String _insets(EdgeInsets insets) {
    return 'l=${_fmt(insets.left)},'
        't=${_fmt(insets.top)},'
        'r=${_fmt(insets.right)},'
        'b=${_fmt(insets.bottom)}';
  }

  static String _fmt(double value) {
    if (value.isInfinite) return 'inf';
    if (value.isNaN) return 'nan';
    return value.toStringAsFixed(1);
  }
}
