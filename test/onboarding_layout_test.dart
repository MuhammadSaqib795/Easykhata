import 'package:digitalkhata/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> expectOnboardingFits(
    WidgetTester tester, {
    required Size size,
    double textScale = 1,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    for (var page = 1; page < 3; page++) {
      await tester.drag(find.byType(PageView), const Offset(-280, 0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    }
  }

  testWidgets('onboarding fits a compact phone at larger text scale', (
    tester,
  ) async {
    await expectOnboardingFits(
      tester,
      size: const Size(320, 480),
      textScale: 1.2,
    );
  });

  testWidgets('onboarding fits a standard phone', (tester) async {
    await expectOnboardingFits(tester, size: const Size(390, 844));
  });
}
