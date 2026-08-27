import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_app/src/providers/auth_provider.dart';
import 'package:xene_app/src/providers/daily_inbox_provider.dart';
import 'package:xene_app/src/providers/soundcloud_connection_provider.dart';
import 'package:xene_app/src/widgets/xene_header.dart';

/// Keeps the real notifier's state shape but skips the network probe its
/// constructor would otherwise fire.
class _StubScNotifier extends ScConnectionNotifier {
  _StubScNotifier(super.ref);

  @override
  Future<void> checkStatus() async {}
}

Widget _headerApp() {
  return ProviderScope(
    overrides: [
      isAnonymousProvider.overrideWith((ref) => false),
      isAdminProvider.overrideWith((ref) async => false),
      dailyInboxProvider.overrideWith((ref) async => null),
      soundcloudConnectionProvider.overrideWith(_StubScNotifier.new),
    ],
    child: const MaterialApp(
      home: Scaffold(body: Column(children: [XeneHeader()])),
    ),
  );
}

ScrollController _navController(WidgetTester tester) {
  final scrollView = tester.widget<SingleChildScrollView>(
    find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    ),
  );
  return scrollView.controller!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('top nav overflow chevron', () {
    testWidgets('tapping it scrolls the nav strip right', (tester) async {
      // Narrow viewport so the nav row overflows and the chevron is shown.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_headerApp());
      await tester.pumpAndSettle();

      final controller = _navController(tester);
      expect(controller.position.maxScrollExtent, greaterThan(0));
      expect(controller.offset, 0);

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(0));
    });

    testWidgets('repeated taps stop at the end and hide the chevron', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_headerApp());
      await tester.pumpAndSettle();

      final controller = _navController(tester);

      // Generous upper bound; the loop breaks as soon as the chevron is gone.
      for (var i = 0; i < 20; i++) {
        final chevron = find.byIcon(Icons.chevron_right);
        if (chevron.evaluate().isEmpty) break;
        await tester.tap(chevron);
        await tester.pumpAndSettle();
      }

      // Hiding the chevron gives the strip its 28px back, so the end-of-scroll
      // extent is re-measured here rather than captured before the taps.
      expect(
        controller.offset,
        moreOrLessEquals(controller.position.maxScrollExtent, epsilon: 4),
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });
  });
}
