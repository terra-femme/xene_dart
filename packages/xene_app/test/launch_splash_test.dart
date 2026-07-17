import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xene_app/src/widgets/launch_splash.dart';

void main() {
  testWidgets('LaunchSplash decodes the animated webp and reports duration', (
    tester,
  ) async {
    Duration? reportedDuration;
    var failed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LaunchSplash(
          onPrimaryAnimationLoaded: (duration) => reportedDuration = duration,
          onPrimaryAnimationFailed: () => failed = true,
        ),
      ),
    );

    // Let the async asset decode + post-frame callbacks settle.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump();

    expect(failed, isFalse, reason: 'splash asset must decode, not fall back');
    expect(reportedDuration, const Duration(seconds: 5));
    expect(find.byType(Image), findsOneWidget);
  });
}
