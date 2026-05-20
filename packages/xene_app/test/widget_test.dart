import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_app/src/layout/xene_layout_metrics.dart';
import 'package:xene_app/src/providers/articles_provider.dart';
import 'package:xene_app/src/providers/feed_provider.dart';
import 'package:xene_app/src/providers/preset_provider.dart';
import 'package:xene_app/src/screens/feed_screen.dart';
import 'package:xene_app/src/widgets/preset_dial.dart';
import 'package:xene_app/src/widgets/xene_content_modal.dart';
import 'package:xene_app/src/widgets/xene_draggable_sheet.dart';
import 'package:xene_app/src/widgets/xene_feed_card.dart';
import 'package:xene_app/src/widgets/xene_sidebar.dart';
import 'package:xene_domain/xene_domain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('responsive metrics', () {
    for (final viewport in _viewportMatrix) {
      test('derive stable metrics for ${viewport.name}', () {
        final metrics = _metricsFor(
          viewport.size,
          safePadding: viewport.safePadding,
          textScaleFactor: viewport.textScaleFactor,
        );

        expect(metrics.viewportSize, viewport.size);
        expect(metrics.headerHeight, greaterThanOrEqualTo(48));
        expect(metrics.sidebarWidth, greaterThan(0));
        expect(metrics.dialKnobSize, greaterThan(0));
        expect(metrics.cardMinHeight, greaterThan(0));
        expect(metrics.sheetMinHeight, greaterThan(0));
        expect(metrics.sheetMaxHeight, greaterThan(metrics.sheetMinHeight));
        expect(metrics.archiveSheetMinRatio, greaterThanOrEqualTo(0.01));
        expect(
          metrics.archiveSheetMaxRatio,
          greaterThan(metrics.archiveSheetMinRatio),
        );
        expect(metrics.archiveSheetMaxRatio, lessThanOrEqualTo(1));
      });
    }

    test('classifies compact widths and short landscape as compact', () {
      final phone = _metricsFor(const Size(390, 844));
      final shortLandscape = _metricsFor(const Size(844, 390));

      expect(phone.layoutClass, XeneLayoutClass.compact);
      expect(shortLandscape.layoutClass, XeneLayoutClass.compact);
      expect(shortLandscape.isShort, isTrue);
    });

    test('classifies tablet and desktop viewports separately', () {
      final tablet = _metricsFor(const Size(768, 1024));
      final desktop = _metricsFor(const Size(1366, 768));

      expect(tablet.layoutClass, XeneLayoutClass.medium);
      expect(desktop.layoutClass, XeneLayoutClass.expanded);
    });

    test('keeps dial and sidebar in bounded ranges', () {
      final compact = _metricsFor(const Size(390, 844));
      final expanded = _metricsFor(const Size(1366, 768));

      expect(compact.sidebarWidth, inInclusiveRange(156, 210));
      expect(expanded.sidebarWidth, inInclusiveRange(180, 224));
      expect(compact.dialKnobSize, inInclusiveRange(72, 96));
      expect(expanded.dialKnobSize, inInclusiveRange(82, 104));
      expect(expanded.dialKnobSize, greaterThanOrEqualTo(compact.dialKnobSize));
    });

    test('accounts for safe-area padding in header and usable height', () {
      final metrics = _metricsFor(
        const Size(390, 844),
        safePadding: const EdgeInsets.only(top: 47, bottom: 21),
      );

      expect(metrics.headerHeight, 103);
      expect(metrics.usableHeight, 776);
      expect(metrics.contentTop, metrics.headerHeight);
    });

    test('carries keyboard/view insets as shell context', () {
      final metrics = _metricsFor(
        const Size(390, 844),
        safePadding: const EdgeInsets.only(top: 47, bottom: 21),
        viewInsets: const EdgeInsets.only(bottom: 320),
      );

      expect(metrics.viewInsets.bottom, 320);
      expect(metrics.usableHeight, 776);
      expect(metrics.toDebugMap()['viewInsets'], contains('320'));
    });

    test(
      'scales control height for larger text without changing shell geometry',
      () {
        final normal = _metricsFor(const Size(768, 1024));
        final large = _metricsFor(const Size(768, 1024), textScaleFactor: 1.4);

        expect(large.feedControlHeight, greaterThan(normal.feedControlHeight));
        expect(large.sidebarWidth, normal.sidebarWidth);
      },
    );

    test('keeps authored sidebar geometry out of shared metrics', () {
      final debugKeys = _metricsFor(const Size(430, 932)).toDebugMap().keys;

      expect(debugKeys, isNot(contains('logoSize')));
      expect(debugKeys, isNot(contains('logoBoxHeight')));
      expect(debugKeys, isNot(contains('logoToDialGap')));
      expect(debugKeys, isNot(contains('articleDockHeight')));
    });
  });

  group('responsive smoke baseline', () {
    for (final viewport in _viewportMatrix) {
      testWidgets('home core widgets build at ${viewport.name}', (
        WidgetTester tester,
      ) async {
        await _setViewport(tester, viewport.size);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _testApp(
            const _HomeSmokeSurface(),
            safePadding: viewport.safePadding,
            textScaleFactor: viewport.textScaleFactor,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
      });

      testWidgets('feed card builds at ${viewport.name}', (
        WidgetTester tester,
      ) async {
        await _setViewport(tester, viewport.size);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _testApp(
            Center(
              child: SizedBox(
                width: viewport.size.width.clamp(180.0, 420.0),
                child: XeneFeedCard(item: _feedItems.first),
              ),
            ),
            safePadding: viewport.safePadding,
            textScaleFactor: viewport.textScaleFactor,
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('preset dial long press overlay builds and dismisses', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(390, 844));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          Center(
            child: PresetDial(
              slots: _presetSlots,
              activeSlug: _presetSlots.first.slug,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(PresetDial));
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();

      expect(tester.takeException(), isNull);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('preset dial respects constraint-provided reserved size', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(390, 844));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          Center(
            child: PresetDial(
              slots: _presetSlots,
              activeSlug: _presetSlots.first.slug,
              knobSize: 72,
              reservedWidth: 130,
              reservedHeight: 148,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(PresetDial)), const Size(130, 148));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sidebar preserves authored XENE logo lockup', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(768, 1024));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(const XeneSidebar()));
      await tester.pump();

      final logoRichText = tester.widget<RichText>(
        find.byWidgetPredicate((widget) {
          return widget is RichText && widget.text.toPlainText() == 'XE\nNE';
        }),
      );

      expect(logoRichText.textAlign, TextAlign.left);
      expect(logoRichText.text.style?.letterSpacing, -0.06 * 375);
      expect(logoRichText.text.style?.height, 0.68);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sidebar preserves logo-safe width clamp', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(390, 844));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(const XeneSidebar()));
      await tester.pump();

      expect(tester.getSize(find.byType(XeneSidebar)).width, 180);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sidebar preserves authored articles dock placement', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(430, 932));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(const XeneSidebar()));
      await tester.pump();
      await tester.pump();

      final articlePager = find.byType(PageView).first;
      final sidebarBottom = tester.getBottomLeft(find.byType(XeneSidebar)).dy;
      final articlePagerBottom = tester.getBottomLeft(articlePager).dy;

      expect(tester.getSize(articlePager).height, 210);
      expect(sidebarBottom - articlePagerBottom, 30);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sidebar compact portrait keeps dial clear of articles', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(320, 568));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          const SizedBox(width: 180, height: 512, child: XeneSidebar()),
          safePadding: const EdgeInsets.only(top: 20),
        ),
      );
      await tester.pump();
      await tester.pump();

      final dialBottom = tester.getBottomLeft(find.byType(PresetDial)).dy;
      final articleTop = tester.getTopLeft(find.byType(PageView).first).dy;
      final articleBottom = tester
          .getBottomLeft(find.byType(PageView).first)
          .dy;
      final sidebarBottom = tester.getBottomLeft(find.byType(XeneSidebar)).dy;

      expect(tester.getSize(find.byType(PageView).first).height, 28);
      expect(dialBottom, lessThanOrEqualTo(articleTop));
      expect(sidebarBottom - articleBottom, 18);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sidebar mini phone keeps preset label away from articles', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(375, 812));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          const SizedBox(width: 180, height: 712, child: XeneSidebar()),
          safePadding: const EdgeInsets.only(top: 44, bottom: 34),
        ),
      );
      await tester.pump();
      await tester.pump();

      final presetLabel = find.text('DNB');
      final articleTop = tester.getTopLeft(find.byType(PageView).first).dy;
      final labelBottom = tester.getBottomLeft(presetLabel).dy;

      expect(presetLabel, findsOneWidget);
      expect(tester.getSize(find.byType(PageView).first).height, 28);
      expect(articleTop - labelBottom, greaterThanOrEqualTo(16));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'sidebar regular phone keeps full articles when label has room',
      (WidgetTester tester) async {
        await _setViewport(tester, const Size(390, 844));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _testApp(
            const SizedBox(width: 180, height: 741, child: XeneSidebar()),
            safePadding: const EdgeInsets.only(top: 47, bottom: 34),
          ),
        );
        await tester.pump();
        await tester.pump();

        final presetLabel = find.text('DNB');
        final articleTop = tester.getTopLeft(find.byType(PageView).first).dy;
        final labelBottom = tester.getBottomLeft(presetLabel).dy;

        expect(presetLabel, findsOneWidget);
        expect(tester.getSize(find.byType(PageView).first).height, 210);
        expect(articleTop - labelBottom, greaterThanOrEqualTo(16));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('sidebar portrait mode does not auto-scroll', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(430, 932));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(const XeneSidebar()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      final scrollable = tester.state<ScrollableState>(
        _sidebarScrollableFinder(),
      );

      expect(scrollable.position.pixels, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'sidebar large landscape does not auto-scroll when content fits',
      (WidgetTester tester) async {
        await _setViewport(tester, const Size(1366, 768));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_testApp(const XeneSidebar()));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        final scrollable = tester.state<ScrollableState>(
          _sidebarScrollableFinder(),
        );

        expect(scrollable.position.pixels, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('sidebar wide medium-height view does not auto-scroll', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(1366, 620));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(const XeneSidebar()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final scrollable = tester.state<ScrollableState>(
        _sidebarScrollableFinder(),
      );
      final sidebarListView = tester.widget<ListView>(find.byType(ListView));

      expect(sidebarListView.physics, isA<NeverScrollableScrollPhysics>());
      expect(scrollable.position.pixels, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'sidebar short landscape auto-scrolls when content is clipped',
      (WidgetTester tester) async {
        await _setViewport(tester, const Size(844, 390));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_testApp(const XeneSidebar()));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        final scrollable = tester.state<ScrollableState>(
          _sidebarScrollableFinder(),
        );
        final sidebarListView = tester.widget<ListView>(find.byType(ListView));

        expect(sidebarListView.physics, isA<ClampingScrollPhysics>());
        expect(scrollable.position.maxScrollExtent, greaterThan(0));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'feed controls stay below just dropped header on wide screens',
      (WidgetTester tester) async {
        await _setViewport(tester, const Size(1366, 768));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_testApp(const FeedScreen()));
        await tester.pump();
        await tester.pump();

        final headerBottom = tester.getBottomLeft(find.text('JUST DROPPED')).dy;
        final filterTop = tester.getTopLeft(find.text('FILTER BY -')).dy;

        expect(filterTop, greaterThanOrEqualTo(headerBottom));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('archive sheet content guardrails build at narrow width', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(320, 568));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(const XeneDraggableSheet()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('CYCLED'), findsOneWidget);
      expect(find.text('FULL GREED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('content modal guardrails build at narrow width', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(320, 568));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          XeneContentModal(
            item: FeedItem(
              id: 'modal-long-content',
              platform: 'a-very-long-platform-name',
              artistName:
                  'An Extremely Long Artist Name That Needs Ellipsis In The Modal Header',
              contentType: 'exceptionally-long-release-type',
              title:
                  'A very long modal title that should wrap naturally without pushing metadata controls outside the modal bounds',
              body:
                  'A modal body with enough text to exercise scrolling without changing the modal outer geometry.',
              externalUrl: 'https://example.com/modal-long-content',
              publishedAt: DateTime(2026, 5, 19),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('A very long modal title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Widget _testApp(
  Widget child, {
  EdgeInsets safePadding = EdgeInsets.zero,
  EdgeInsets viewInsets = EdgeInsets.zero,
  double textScaleFactor = 1,
}) {
  return ProviderScope(
    overrides: [
      presetDialProvider.overrideWith(_TestPresetDialNotifier.new),
      presetArticlesProvider.overrideWith((ref) async => _articles),
      feedProvider.overrideWith(_TestFeedNotifier.new),
      archiveFetchProvider.overrideWith(_TestArchiveFetchNotifier.new),
      feedEffectiveDateProvider.overrideWith((ref) => DateTime(2026, 5, 19)),
    ],
    child: MaterialApp(
      builder: (context, appChild) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            padding: safePadding,
            viewPadding: safePadding,
            viewInsets: viewInsets,
            textScaler: TextScaler.linear(textScaleFactor),
          ),
          child: appChild ?? const SizedBox.shrink(),
        );
      },
      home: Scaffold(body: child),
    ),
  );
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
}

Finder _sidebarScrollableFinder() {
  return find.descendant(
    of: find.byType(ListView).first,
    matching: find.byType(Scrollable),
  );
}

XeneLayoutMetrics _metricsFor(
  Size size, {
  EdgeInsets safePadding = EdgeInsets.zero,
  EdgeInsets viewInsets = EdgeInsets.zero,
  double textScaleFactor = 1,
}) {
  return XeneLayoutMetrics.fromConstraints(
    constraints: BoxConstraints.tight(size),
    safePadding: safePadding,
    viewInsets: viewInsets,
    textScaleFactor: textScaleFactor,
  );
}

class _HomeSmokeSurface extends StatelessWidget {
  const _HomeSmokeSurface();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            XeneSidebar(),
            Expanded(child: FeedScreen()),
          ],
        ),
        XeneDraggableSheet(),
      ],
    );
  }
}

class _TestPresetDialNotifier extends PresetDialNotifier {
  @override
  Future<PresetDialState> build() async {
    return PresetDialState(
      slots: _presetSlots,
      activePresetSlug: _presetSlots.first.slug,
      defaultPresetSlug: _presetSlots.first.slug,
    );
  }
}

class _TestFeedNotifier extends FeedNotifier {
  @override
  Future<List<FeedItem>> build() async => _feedItems;
}

class _TestArchiveFetchNotifier extends ArchiveFetchNotifier {
  @override
  Future<List<FeedItem>> build() async => _archiveItems;

  @override
  Future<void> fetchOnce() async {}

  @override
  Future<void> fetchNextPage({bool showInitialLoading = false}) async {}
}

class _ViewportCase {
  const _ViewportCase(
    this.name,
    this.size, {
    this.safePadding = EdgeInsets.zero,
    this.textScaleFactor = 1,
  });

  final String name;
  final Size size;
  final EdgeInsets safePadding;
  final double textScaleFactor;
}

const _viewportMatrix = [
  _ViewportCase(
    'narrow phone portrait',
    Size(390, 844),
    safePadding: EdgeInsets.only(top: 47, bottom: 21),
  ),
  _ViewportCase(
    'tall phone portrait',
    Size(430, 932),
    safePadding: EdgeInsets.only(top: 59, bottom: 34),
    textScaleFactor: 1.25,
  ),
  _ViewportCase('short landscape', Size(844, 390)),
  _ViewportCase('tablet portrait', Size(768, 1024)),
  _ViewportCase('tablet landscape', Size(1024, 768), textScaleFactor: 1.15),
  _ViewportCase('desktop', Size(1366, 768)),
  _ViewportCase('short desktop', Size(1440, 540)),
];

const _presetSlots = [
  PresetSlot(
    slug: 'dnb-foundations',
    name: 'DNB',
    notchIndex: 0,
    themeColor: Color(0xFFFF5500),
    isDefault: true,
  ),
  PresetSlot(
    slug: 'leftfield',
    name: 'Leftfield',
    notchIndex: 3,
    themeColor: Color(0xFF00A88F),
  ),
  PresetSlot(
    slug: 'breaks',
    name: 'Breaks',
    notchIndex: 8,
    themeColor: Color(0xFF9146FF),
  ),
];

final _articles = [
  ArticleItem(
    title: 'Scene Report: Constraint Driven Club Tools',
    url: 'https://example.com/article',
    snippet:
        'A compact article summary that gives the sidebar enough text to size.',
    source: 'Xene Test',
    publishedAt: DateTime(2026, 5, 19),
  ),
  ArticleItem(
    title: 'New Interfaces for Fast Feeds',
    url: 'https://example.com/article-two',
    snippet: 'Another summary for carousel layout coverage.',
    source: 'Xene Test',
    publishedAt: DateTime(2026, 5, 18),
  ),
];

final _feedItems = List<FeedItem>.generate(12, (index) {
  final platforms = ['soundcloud', 'bandcamp', 'youtube'];
  return FeedItem(
    id: 'recent-$index',
    platform: platforms[index % platforms.length],
    artistName: 'Artist ${index % 4}',
    contentType: index.isEven ? 'track' : 'mix',
    title: 'Responsive Baseline Item ${index + 1}',
    body: 'A feed card body long enough to exercise ellipsis behavior.',
    externalUrl: 'https://example.com/recent-$index',
    publishedAt: DateTime(2026, 5, 19).subtract(Duration(hours: index * 7)),
    isNew: index < 2,
  );
});

final _archiveItems = List<FeedItem>.generate(8, (index) {
  return FeedItem(
    id: 'archive-$index',
    platform: index.isEven ? 'soundcloud' : 'bandcamp',
    artistName: 'Archive Artist ${index % 3}',
    contentType: 'release',
    title: 'Archive Baseline Item ${index + 1}',
    body: 'Archive card body for draggable sheet coverage.',
    externalUrl: 'https://example.com/archive-$index',
    publishedAt: DateTime(2026, 5, 10).subtract(Duration(days: index)),
  );
});
