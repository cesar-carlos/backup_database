import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lightFluentTheme registers AppSemanticColors.light', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        home: Builder(
          builder: (context) {
            expect(
              FluentTheme.of(context).extension<AppSemanticColors>(),
              AppSemanticColors.light,
            );
            expect(
              context.appSemanticColors.surface,
              AppSemanticColors.light.surface,
            );
            return const SizedBox();
          },
        ),
      ),
    );
  });

  testWidgets('darkFluentTheme registers AppSemanticColors.dark', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.darkFluentTheme,
        home: Builder(
          builder: (context) {
            expect(
              FluentTheme.of(context).extension<AppSemanticColors>(),
              AppSemanticColors.dark,
            );
            return const SizedBox();
          },
        ),
      ),
    );
  });

  testWidgets('lightTheme registers AppSemanticColors.light', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) {
            expect(
              Theme.of(context).extension<AppSemanticColors>(),
              AppSemanticColors.light,
            );
            return const SizedBox();
          },
        ),
      ),
    );
  });

  testWidgets('darkTheme registers AppSemanticColors.dark', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            expect(
              Theme.of(context).extension<AppSemanticColors>(),
              AppSemanticColors.dark,
            );
            return const SizedBox();
          },
        ),
      ),
    );
  });
}
