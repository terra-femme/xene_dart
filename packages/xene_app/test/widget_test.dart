import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_app/src/layout/xene_layout_metrics.dart';
import 'package:xene_app/src/providers/articles_provider.dart';
import 'package:xene_app/src/providers/artists_provider.dart';
import 'package:xene_app/src/providers/discovery_provider.dart';
import 'package:xene_app/src/providers/feed_provider.dart';
import 'package:xene_app/src/providers/following_provider.dart';
import 'package:xene_app/src/providers/graph_provider.dart';
import 'package:xene_app/src/providers/monitor_provider.dart';
import 'package:xene_app/src/providers/preset_provider.dart';
import 'package:xene_app/src/providers/preset_sources_provider.dart';
import 'package:xene_app/src/providers/preset_templates_provider.dart';
import 'package:xene_app/src/providers/player_provider.dart';
import 'package:xene_app/src/providers/sc_search_provider.dart';
import 'package:xene_app/src/providers/soundcloud_connection_provider.dart';
import 'package:xene_app/src/screens/artist_detail_screen.dart';
import 'package:xene_app/src/screens/artists_screen.dart';
import 'package:xene_app/src/screens/articles_screen.dart';
import 'package:xene_app/src/screens/feed_screen.dart';
import 'package:xene_app/src/screens/monitor_screen.dart';
import 'package:xene_app/src/screens/network_screen.dart';
import 'package:xene_app/src/screens/preset_playground_screen.dart';
import 'package:xene_app/src/widgets/logo_pip_player.dart';
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

    testWidgets('feed card wraps long badges at narrow feed width', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(320, 568));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          Center(
            child: SizedBox(
              width: 132,
              child: XeneFeedCard(item: _longMetadataFeedItem),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('EXCEPTIONALLY-LONG-RELEASE-TYPE'), findsOneWidget);
      expect(find.text('A-VERY-LONG-PLATFORM-NAME'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

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

        final headerBand = find.byKey(const ValueKey('feedHeaderBand'));
        final controlsBar = find.byKey(const ValueKey('feedControlsBar'));
        final feedBody = find.byKey(const ValueKey('feedBodyStack'));

        final headerBottom = tester.getBottomLeft(headerBand).dy;
        final controlsTop = tester.getTopLeft(controlsBar).dy;
        final controlsBottom = tester.getBottomLeft(controlsBar).dy;
        final feedBodyTop = tester.getTopLeft(feedBody).dy;

        expect(controlsTop, greaterThanOrEqualTo(headerBottom));
        expect(controlsTop - headerBottom, lessThanOrEqualTo(1));
        expect(feedBodyTop, greaterThanOrEqualTo(controlsBottom));
        expect(feedBodyTop - controlsBottom, lessThanOrEqualTo(1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('feed controls keep authored left and right alignment', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(1366, 768));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(const FeedScreen()));
      await tester.pump();
      await tester.pump();

      final controlsRect = tester.getRect(
        find.byKey(const ValueKey('feedControlsBar')),
      );
      final sevenDaysRect = tester.getRect(find.text('\u2264 7 DAYS'));
      final filterRect = tester.getRect(find.text('FILTER BY -'));
      final searchRect = tester.getRect(find.byIcon(Icons.search));

      expect(sevenDaysRect.left, closeTo(controlsRect.left + 16, 1));
      expect(filterRect.left, greaterThan(sevenDaysRect.right));
      expect(searchRect.left, greaterThan(filterRect.right));
      expect(searchRect.right, lessThanOrEqualTo(controlsRect.right));
      expect(tester.takeException(), isNull);
    });

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

    testWidgets('content modal artwork stays within narrow content width', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(260, 568));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          SizedBox(
            width: 180,
            child: XeneContentModal(item: _playableLongMetadataFeedItem),
          ),
        ),
      );
      await tester.pump();

      final modalRect = tester.getRect(find.byType(XeneContentModal));
      final artworkRect = tester.getRect(
        find.byKey(const ValueKey('contentModalArtwork')),
      );

      expect(artworkRect.width, lessThanOrEqualTo(200));
      expect(artworkRect.left, greaterThanOrEqualTo(modalRect.left));
      expect(artworkRect.right, lessThanOrEqualTo(modalRect.right));
      expect(tester.takeException(), isNull);
    });

    testWidgets('logo pip player preserves locked outer geometry', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(390, 844));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          const Stack(children: [LogoPipPlayer()]),
          overrides: [
            playerProvider.overrideWith((ref) => _VisiblePlayerNotifier(ref)),
          ],
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byKey(const ValueKey('logoPipPlayerSurface'))),
        const Size(175, 275),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('artists narrow panels derive height from viewport', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(390, 640));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(const ArtistsScreen(), overrides: _artistsScreenOverrides()),
      );
      await tester.pump();
      await tester.pump();

      final panelHeight = tester
          .getSize(find.byKey(const ValueKey('artistsFollowingPanel')))
          .height;

      expect(panelHeight, inInclusiveRange(360, 520));
      expect(panelHeight, isNot(460));
      expect(tester.takeException(), isNull);
    });

    testWidgets('preset playground narrow panes derive local heights', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(390, 640));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          const PresetPlaygroundScreen(),
          overrides: _presetPlaygroundOverrides(),
        ),
      );
      await tester.pump();
      await tester.pump();

      final templateHeight = tester
          .getSize(find.byKey(const ValueKey('presetTemplateListPane')))
          .height;

      expect(templateHeight, inInclusiveRange(300, 420));
      expect(templateHeight, isNot(360));
      expect(tester.takeException(), isNull);
    });

    testWidgets('monitor buckets stack on narrow screens', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(390, 640));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          const MonitorScreen(),
          overrides: [
            monitorProvider.overrideWith((ref) => Stream.value(_monitorStats)),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      final onboardingRect = tester.getRect(
        find.byKey(const ValueKey('monitorOnboardingBucket')),
      );
      final upkeepRect = tester.getRect(
        find.byKey(const ValueKey('monitorUpkeepBucket')),
      );

      expect(upkeepRect.top, greaterThan(onboardingRect.bottom));
      expect(upkeepRect.left, closeTo(onboardingRect.left, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('network graph clips long hub labels and badges locally', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(320, 568));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          const NetworkScreen(),
          overrides: [
            discoveryStatusProvider.overrideWith(
              (ref) async => {
                'has_providers': true,
                'providers': ['gemini-provider-with-a-very-long-name'],
              },
            ),
            graphProvider.overrideWith((ref) async => _networkGraph),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('networkHubCard_hub-long')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('artist detail clips long title inside app bar', (
      WidgetTester tester,
    ) async {
      await _setViewport(tester, const Size(320, 568));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(ArtistDetailScreen(artist: _detailArtist)),
      );
      await tester.pump();
      await tester.pump();

      final titleFinder = find.byKey(const ValueKey('artistDetailTitle'));
      expect(titleFinder, findsWidgets);

      final title = tester.widgetList<Text>(titleFinder).first;

      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(
        find.byKey(const ValueKey('artistDetailPlatformLinks')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'features landscape cover lift still reaches bottom at scroll end',
      (WidgetTester tester) async {
        await _setViewport(tester, const Size(844, 390));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _testApp(
            const ArticlesScreen(),
            overrides: [
              featuredArticlesProvider.overrideWith((ref) async => _articles),
              magazineCoverProvider.overrideWith((ref) async => _magazineCover),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pump();

        final stripBottom = tester
            .getBottomLeft(find.byKey(const ValueKey('landscapeArticleStrip')))
            .dy;

        expect(stripBottom, greaterThanOrEqualTo(390));
        expect(tester.takeException(), isNull);
      },
    );

    for (final viewport in _mobileReadinessViewportMatrix) {
      for (final screen in _secondaryScreenSmokeCases) {
        testWidgets(
          '${screen.name} secondary screen builds at ${viewport.name}',
          (WidgetTester tester) async {
            await _setViewport(tester, viewport.size);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              _testApp(
                screen.builder(),
                safePadding: viewport.safePadding,
                textScaleFactor: viewport.textScaleFactor,
                overrides: screen.overrides?.call() ?? const [],
              ),
            );
            await tester.pump();
            await tester.pump();

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}

Widget _testApp(
  Widget child, {
  EdgeInsets safePadding = EdgeInsets.zero,
  EdgeInsets viewInsets = EdgeInsets.zero,
  double textScaleFactor = 1,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      presetDialProvider.overrideWith(_TestPresetDialNotifier.new),
      presetArticlesProvider.overrideWith((ref) async => _articles),
      feedProvider.overrideWith(_TestFeedNotifier.new),
      archiveFetchProvider.overrideWith(_TestArchiveFetchNotifier.new),
      feedEffectiveDateProvider.overrideWith((ref) => DateTime(2026, 5, 19)),
      ...overrides,
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

class _VisiblePlayerNotifier extends PlayerNotifier {
  _VisiblePlayerNotifier(super.ref) {
    state = PlayerState(
      currentTrack: _playableLongMetadataFeedItem,
      activePlatform: ActivePlatform.none,
      isVisible: true,
    );
  }
}

List<Override> _artistsScreenOverrides() {
  return [
    artistsProvider.overrideWith(_TestArtistsNotifier.new),
    soundcloudConnectionProvider.overrideWith(
      (ref) => _TestScConnectionNotifier(ref),
    ),
    followingProvider.overrideWith((ref) => _TestFollowingNotifier(ref)),
    scSearchProvider.overrideWith((ref) => _TestScSearchNotifier(ref)),
    discoveryProvider.overrideWith((ref) => _TestDiscoveryNotifier(ref)),
  ];
}

List<Override> _presetPlaygroundOverrides() {
  return [
    presetTemplatesProvider.overrideWith(_TestPresetTemplatesNotifier.new),
    presetSourcesProvider.overrideWith(
      (ref) => _TestPresetSourcesNotifier(ref),
    ),
    scSearchProvider.overrideWith((ref) => _TestScSearchNotifier(ref)),
  ];
}

class _TestArtistsNotifier extends ArtistsNotifier {
  @override
  Future<List<Artist>> build() async => _artists;

  @override
  Future<void> refresh() async {
    state = AsyncData(_artists);
  }

  @override
  Future<void> deleteArtist(String id) async {}
}

class _TestPresetTemplatesNotifier extends PresetTemplatesNotifier {
  @override
  Future<List<PresetTemplate>> build() async => _presetTemplates;

  @override
  Future<void> refresh() async {
    state = AsyncData(_presetTemplates);
  }

  @override
  Future<void> create(Map<String, dynamic> data) async {}

  @override
  Future<void> updateTemplate(
    String originalSlug,
    Map<String, dynamic> data,
  ) async {}
}

class _TestPresetSourcesNotifier extends PresetSourcesNotifier {
  _TestPresetSourcesNotifier(super.ref);

  @override
  Future<void> load(String slug) async {
    state = PresetSourcesState(slug: slug, sources: _presetSources);
  }

  @override
  Future<void> addSoundCloudSource(
    String slug,
    Map<String, dynamic> candidate,
  ) async {}

  @override
  Future<void> removeSource(String slug, String sourceId) async {}

  @override
  Future<Map<String, dynamic>?> refreshSource(
    String slug,
    String sourceId,
  ) async {
    return null;
  }

  @override
  Future<Map<String, dynamic>?> refreshAll(String slug) async {
    return null;
  }

  @override
  Future<void> patchSource(
    String slug,
    String sourceId, {
    String? bandcampUrl,
    String? youtubeUrl,
  }) async {}

  @override
  Future<void> addArticle(
    String slug,
    String sourceId, {
    required String title,
    required String url,
    String? snippet,
    String? source,
  }) async {}

  @override
  Future<void> preview(String slug) async {
    state = state.copyWith(previewItems: _feedItems.take(2).toList());
  }
}

class _TestScConnectionNotifier extends ScConnectionNotifier {
  _TestScConnectionNotifier(super.ref) {
    state = const ScConnectionState(status: ScConnectionStatus.disconnected);
  }

  @override
  Future<void> checkStatus() async {}

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {
    state = const ScConnectionState(status: ScConnectionStatus.disconnected);
  }
}

class _TestFollowingNotifier extends FollowingNotifier {
  _TestFollowingNotifier(super.ref);

  @override
  Future<void> fetch({bool force = false}) async {}

  @override
  void reset() {
    state = const FollowingState();
  }
}

class _TestScSearchNotifier extends ScSearchNotifier {
  _TestScSearchNotifier(super.ref);

  @override
  Future<void> search(String query) async {}

  @override
  void clear() {
    state = const ScSearchState();
  }
}

class _TestDiscoveryNotifier extends DiscoveryNotifier {
  _TestDiscoveryNotifier(super.ref);

  @override
  Future<void> autoDiscover(String name, {String? scProfileUrl}) async {}

  @override
  Future<void> saveDiscovery(Map<String, dynamic> result) async {}

  @override
  void reset() {
    state = const DiscoveryState();
  }
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

class _SecondaryScreenSmokeCase {
  const _SecondaryScreenSmokeCase(
    this.name, {
    required this.builder,
    this.overrides,
  });

  final String name;
  final Widget Function() builder;
  final List<Override> Function()? overrides;
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

const _mobileReadinessViewportMatrix = [
  _ViewportCase(
    'iPhone SE portrait',
    Size(320, 568),
    safePadding: EdgeInsets.only(top: 20),
  ),
  _ViewportCase(
    'small notched phone',
    Size(375, 812),
    safePadding: EdgeInsets.only(top: 47, bottom: 34),
  ),
  _ViewportCase(
    'large text phone',
    Size(390, 844),
    safePadding: EdgeInsets.only(top: 47, bottom: 21),
    textScaleFactor: 1.35,
  ),
  _ViewportCase('phone landscape', Size(844, 390)),
  _ViewportCase('tablet portrait', Size(768, 1024)),
];

final _secondaryScreenSmokeCases = [
  _SecondaryScreenSmokeCase(
    'artists',
    builder: () => const ArtistsScreen(),
    overrides: _artistsScreenOverrides,
  ),
  _SecondaryScreenSmokeCase(
    'preset playground',
    builder: () => const PresetPlaygroundScreen(),
    overrides: _presetPlaygroundOverrides,
  ),
  _SecondaryScreenSmokeCase(
    'monitor',
    builder: () => const MonitorScreen(),
    overrides: () => [
      monitorProvider.overrideWith((ref) => Stream.value(_monitorStats)),
    ],
  ),
  _SecondaryScreenSmokeCase(
    'network',
    builder: () => const NetworkScreen(),
    overrides: () => [
      discoveryStatusProvider.overrideWith(
        (ref) async => {
          'has_providers': true,
          'providers': ['gemini-provider-with-a-very-long-name'],
        },
      ),
      graphProvider.overrideWith((ref) async => _networkGraph),
    ],
  ),
  _SecondaryScreenSmokeCase(
    'artist detail',
    builder: () => ArtistDetailScreen(artist: _detailArtist),
  ),
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

const _presetTemplates = [
  PresetTemplate(
    slug: 'dnb-foundations',
    name: 'DNB Foundations',
    notchIndex: 0,
    themeColor: '#FF5500',
    isDefault: true,
    enabled: true,
    description: 'Baseline preset for narrow playground tests.',
  ),
  PresetTemplate(
    slug: 'leftfield',
    name: 'Leftfield',
    notchIndex: 3,
    themeColor: '#00A88F',
    isDefault: false,
    enabled: true,
  ),
];

const _presetSources = [
  PresetSource(
    id: 'source-1',
    displayName: 'Constraint Operator',
    enabled: true,
    soundcloudUsername: 'constraint-operator',
    soundcloudUrl: 'https://soundcloud.com/constraint-operator',
    manuallyVerified: true,
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

const _magazineCover = MagazineCover(
  id: 'cover-layout-regression',
  title: 'Layout Regression Cover',
  backgroundImageUrl: '',
  aspectRatio: '3:4',
);

final _artists = [
  Artist(
    id: 'artist-1',
    name: 'Constraint Operator',
    soundcloudUsername: 'constraint-operator',
    soundcloudUrl: 'https://soundcloud.com/constraint-operator',
    createdAt: DateTime(2026, 5, 19),
  ),
  Artist(
    id: 'artist-2',
    name: 'Adaptive Layout Crew',
    soundcloudUsername: 'adaptive-layout-crew',
    soundcloudUrl: 'https://soundcloud.com/adaptive-layout-crew',
    createdAt: DateTime(2026, 5, 18),
  ),
];

final _detailArtist = Artist(
  id: 'artist-detail-long',
  name:
      'An Extremely Long Artist Detail Screen Name That Must Stay Inside The App Bar',
  soundcloudUsername: 'artist-detail-long',
  soundcloudUrl: 'https://soundcloud.com/artist-detail-long',
  youtubeUrl: 'https://youtube.com/@artist-detail-long',
  spotifyUrl: 'https://open.spotify.com/artist/detail-long',
  bandcampUrl: 'https://artist-detail-long.bandcamp.com',
  instagramUrl: 'https://instagram.com/artist_detail_long',
  websiteUrl: 'https://example.com/artist-detail-long',
  createdAt: DateTime(2026, 5, 19),
);

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

final _longMetadataFeedItem = FeedItem(
  id: 'long-metadata-card',
  platform: 'a-very-long-platform-name',
  artistName: 'An Extremely Long Artist Name That Needs Ellipsis',
  contentType: 'exceptionally-long-release-type',
  title:
      'A narrow feed card title that should wrap without forcing badge overflow',
  body: 'A compact body that should stay inside the card bounds.',
  externalUrl: 'https://example.com/long-metadata-card',
  publishedAt: DateTime(2026, 5, 19),
  isNew: true,
);

final _playableLongMetadataFeedItem = FeedItem(
  id: 'playable-long-metadata-card',
  platform: 'youtube',
  artistName: 'An Extremely Long Playable Artist Name That Needs Ellipsis',
  contentType: 'exceptionally-long-playable-release-type',
  title:
      'A playable modal title that should wrap without changing modal geometry',
  body: 'A compact playable modal body for content guardrail coverage.',
  externalUrl: 'https://youtube.com/watch?v=playable-long-metadata-card',
  publishedAt: DateTime(2026, 5, 19),
);

final _monitorStats = <String, dynamic>{
  'gemini': {
    'keyCount': 2,
    'currentKeyIndex': 1,
    'rotations': 3,
    'hasKeys': true,
  },
  'onboarding': {
    'calls': 12,
    'inputTokens': 24000,
    'outputTokens': 3200,
    'groundedCalls': 9,
    'estimatedCostUsd': '0.042',
  },
  'upkeep': {
    'calls': 7,
    'inputTokens': 18000,
    'outputTokens': 2100,
    'groundedCalls': 6,
    'estimatedCostUsd': '0.031',
  },
  'perKey': [
    {'keyIndex': 1, 'calls': 10, 'inputTokens': 22000, 'groundedCalls': 8},
  ],
  'recentCalls': [
    {
      'context': 'press_scout.batch.long_context_for_ellipsis',
      'inputTokens': 9000,
      'grounded': true,
      'timestamp': '2026-05-19T18:30:00.000Z',
    },
  ],
};

final _networkGraph = <String, dynamic>{
  'nodes': [
    {
      'id': 'hub-long',
      'type': 'HUB',
      'label':
          'An Extremely Long Artist Identity Graph Hub Name That Must Ellipsize',
      'data': {
        'entityType': 'artist-with-a-very-long-type-label',
        'identityConfidence': 'HIGH',
        'coverageLevel':
            'EXTREMELY-LONG-COVERAGE-LABEL-THAT-SHOULD-NOT-OVERFLOW',
      },
    },
    {
      'id': 'platform-long',
      'type': 'DATA_POINT',
      'label':
          'soundcloud.com/a-path-with-an-exceptionally-long-artist-identity-url',
      'data': {'url': 'https://example.com/platform-long'},
    },
    {
      'id': 'analysis-long',
      'type': 'ANALYSIS',
      'label': 'analysis',
      'data': {
        'text':
            'This analysis copy is intentionally long enough to verify the card keeps text inside the existing graph composition on phone-width surfaces.',
      },
    },
  ],
  'links': [
    {'source': 'hub-long', 'target': 'platform-long'},
    {'source': 'hub-long', 'target': 'analysis-long'},
  ],
};

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
