import 'package:flutter/widgets.dart';
import 'package:xene_app/src/layout/xene_responsive_debug.dart';

enum XeneLayoutClass { compact, medium, expanded }

class XeneLayoutMetrics {
  const XeneLayoutMetrics({
    required this.viewportSize,
    required this.safePadding,
    required this.viewInsets,
    required this.layoutClass,
    required this.textScaleFactor,
    required this.headerHeight,
    required this.innerHeaderHeight,
    required this.sidebarWidth,
    required this.sidebarPadding,
    required this.dialKnobSize,
    required this.dialReservedWidth,
    required this.dialReservedHeight,
    required this.feedHeaderHeight,
    required this.feedControlHeight,
    required this.feedBottomSpacer,
    required this.cardMinHeight,
    required this.cardThumbnailSize,
    required this.sheetMinHeight,
    required this.sheetMaxHeight,
    required this.playerWidth,
    required this.playerHeight,
    required this.contentHorizontalPadding,
  });

  factory XeneLayoutMetrics.fromConstraints({
    required BoxConstraints constraints,
    required EdgeInsets safePadding,
    EdgeInsets viewInsets = EdgeInsets.zero,
    required double textScaleFactor,
  }) {
    final width = _finiteOrZero(constraints.maxWidth);
    final height = _finiteOrZero(constraints.maxHeight);
    final usableHeight = (height - safePadding.top - safePadding.bottom).clamp(
      0.0,
      double.infinity,
    );
    final shortestSide = width < height ? width : height;
    final layoutClass = width < 600 || shortestSide < 420
        ? XeneLayoutClass.compact
        : width < 1024
        ? XeneLayoutClass.medium
        : XeneLayoutClass.expanded;
    final compactHeight = usableHeight < 640;
    final textScaleAdjustment = textScaleFactor.clamp(1.0, 1.35);

    final innerHeaderHeight = compactHeight ? 48.0 : 56.0;
    final headerHeight = safePadding.top + innerHeaderHeight;
    final sidebarWidth = (width * 0.30).clamp(
      layoutClass == XeneLayoutClass.compact ? 156.0 : 180.0,
      layoutClass == XeneLayoutClass.expanded ? 224.0 : 210.0,
    );
    final dialKnobSize = (usableHeight * 0.14).clamp(
      compactHeight ? 72.0 : 82.0,
      layoutClass == XeneLayoutClass.expanded ? 104.0 : 96.0,
    );

    final metrics = XeneLayoutMetrics(
      viewportSize: Size(width, height),
      safePadding: safePadding,
      viewInsets: viewInsets,
      layoutClass: layoutClass,
      textScaleFactor: textScaleFactor,
      headerHeight: headerHeight,
      innerHeaderHeight: innerHeaderHeight,
      sidebarWidth: sidebarWidth.toDouble(),
      sidebarPadding: layoutClass == XeneLayoutClass.compact ? 10.0 : 12.0,
      dialKnobSize: dialKnobSize.toDouble(),
      dialReservedWidth: (dialKnobSize + 58.0).clamp(130.0, 170.0).toDouble(),
      dialReservedHeight: (dialKnobSize + 76.0).clamp(148.0, 200.0).toDouble(),
      feedHeaderHeight: compactHeight ? 56.0 : 72.0,
      feedControlHeight: (32.0 * textScaleAdjustment).clamp(32.0, 42.0),
      feedBottomSpacer: compactHeight ? 72.0 : 100.0,
      cardMinHeight: compactHeight ? 82.0 : 92.0,
      cardThumbnailSize: compactHeight ? 34.0 : 39.0,
      sheetMinHeight: 23.0,
      sheetMaxHeight: (usableHeight * 0.72).clamp(180.0, usableHeight),
      playerWidth: (width * 0.18).clamp(150.0, 220.0),
      playerHeight: (usableHeight * 0.34).clamp(220.0, 320.0),
      contentHorizontalPadding: layoutClass == XeneLayoutClass.compact
          ? 12.0
          : 16.0,
    );

    XeneResponsiveDebug.constraints(
      'LayoutMetrics.fromConstraints',
      constraints,
    );
    XeneResponsiveDebug.values('LayoutMetrics', metrics.toDebugMap());

    return metrics;
  }

  final Size viewportSize;
  final EdgeInsets safePadding;
  final EdgeInsets viewInsets;
  final XeneLayoutClass layoutClass;
  final double textScaleFactor;
  final double headerHeight;
  final double innerHeaderHeight;
  final double sidebarWidth;
  final double sidebarPadding;
  final double dialKnobSize;
  final double dialReservedWidth;
  final double dialReservedHeight;
  final double feedHeaderHeight;
  final double feedControlHeight;
  final double feedBottomSpacer;
  final double cardMinHeight;
  final double cardThumbnailSize;
  final double sheetMinHeight;
  final double sheetMaxHeight;
  final double playerWidth;
  final double playerHeight;
  final double contentHorizontalPadding;

  double get usableHeight {
    return (viewportSize.height - safePadding.top - safePadding.bottom).clamp(
      0.0,
      double.infinity,
    );
  }

  double get contentTop {
    return headerHeight;
  }

  bool get isCompact {
    return layoutClass == XeneLayoutClass.compact;
  }

  bool get isMedium {
    return layoutClass == XeneLayoutClass.medium;
  }

  bool get isExpanded {
    return layoutClass == XeneLayoutClass.expanded;
  }

  bool get isShort {
    return usableHeight < 640;
  }

  double get estimatedFeedHeaderExtent {
    return feedHeaderHeight + feedControlHeight;
  }

  double get archiveSheetMaxRatio {
    if (viewportSize.height <= 0) return 0.1;
    return (sheetMaxHeight / viewportSize.height).clamp(0.1, 1.0);
  }

  double get archiveSheetMinRatio {
    if (viewportSize.height <= 0) return 0.01;
    return (sheetMinHeight / viewportSize.height).clamp(0.01, 1.0);
  }

  Map<String, Object?> toDebugMap() {
    return {
      'viewport': '${viewportSize.width}x${viewportSize.height}',
      'class': layoutClass.name,
      'usableHeight': usableHeight,
      'safePadding': safePadding.toString(),
      'viewInsets': viewInsets.toString(),
      'headerHeight': headerHeight,
      'sidebarWidth': sidebarWidth,
      'dialKnobSize': dialKnobSize,
      'feedHeaderHeight': feedHeaderHeight,
      'cardMinHeight': cardMinHeight,
      'sheetMinHeight': sheetMinHeight,
      'sheetMaxHeight': sheetMaxHeight,
    };
  }

  static double _finiteOrZero(double value) {
    if (value.isFinite) return value;
    return 0;
  }
}

class XeneLayoutScope extends InheritedWidget {
  const XeneLayoutScope({
    super.key,
    required this.metrics,
    required super.child,
  });

  final XeneLayoutMetrics metrics;

  static XeneLayoutMetrics of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<XeneLayoutScope>();
    assert(scope != null, 'No XeneLayoutScope found in context.');
    return scope!.metrics;
  }

  static XeneLayoutMetrics? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<XeneLayoutScope>()
        ?.metrics;
  }

  @override
  bool updateShouldNotify(covariant XeneLayoutScope oldWidget) {
    return metrics != oldWidget.metrics;
  }
}
