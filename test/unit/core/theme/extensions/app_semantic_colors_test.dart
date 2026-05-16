import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSemanticColors', () {
    test('lerp at t=0 returns first colors', () {
      final mid = AppSemanticColors.light.lerp(AppSemanticColors.dark, 0);
      expect(mid.success, AppSemanticColors.light.success);
    });

    test('lerp at t=1 returns second colors', () {
      final end = AppSemanticColors.light.lerp(AppSemanticColors.dark, 1);
      expect(end.success, AppSemanticColors.dark.success);
    });

    test('lerp at t=0.5 blends', () {
      final blended = AppSemanticColors.light.lerp(AppSemanticColors.dark, 0.5);
      expect(blended.success, isNot(equals(AppSemanticColors.light.success)));
      expect(blended.success, isNot(equals(AppSemanticColors.dark.success)));
    });

    test('copyWith overrides single field', () {
      final c = AppSemanticColors.light.copyWith(
        danger: const Color(0xFF000000),
      );
      expect(c.danger, const Color(0xFF000000));
      expect(c.success, AppSemanticColors.light.success);
    });
  });

  group('AppSemanticColorsContext', () {
    testWidgets('falls back to light when theme has no extension', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const <ThemeExtension<dynamic>>[],
          ),
          home: Builder(
            builder: (context) {
              expect(
                context.appSemanticColors.success,
                AppSemanticColors.light.success,
              );
              expect(
                context.colors.success,
                AppSemanticColors.light.success,
              );
              return const SizedBox();
            },
          ),
        ),
      );
    });
  });
}
