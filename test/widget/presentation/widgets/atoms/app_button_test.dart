import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/app_density.dart';
import 'package:backup_database/core/theme/tokens/app_target_size.dart';
import 'package:backup_database/presentation/providers/app_density_provider.dart';
import 'package:backup_database/presentation/widgets/atoms/app_button.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

FluentThemeData _theme() {
  return FluentThemeData.light().copyWith(
    extensions: const [AppSemanticColors.light],
  );
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    FluentApp(
      theme: _theme(),
      home: InheritedAppDensity(
        density: AppDensity.compact,
        child: ScaffoldPage(content: Center(child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('default AppButton uses Button, not FilledButton', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      AppButton(label: 'Save', onPressed: () {}),
    );

    expect(find.widgetWithText(Button, 'Save'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('AppButton.primary uses FilledButton', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      AppButton.primary(label: 'Confirm', onPressed: () {}),
    );

    expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);
    expect(find.widgetWithText(Button, 'Confirm'), findsNothing);
  });

  testWidgets('AppButton.primary loading keeps FilledButton and label', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      AppButton.primary(
        label: 'Install service',
        isLoading: true,
        loadingLabel: 'Waiting for UAC...',
        onPressed: () {},
      ),
    );

    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(ProgressRing), findsOneWidget);
    expect(find.text('Waiting for UAC...'), findsOneWidget);
    final filled = tester.widget<FilledButton>(
      find.descendant(
        of: find.byType(AppButton),
        matching: find.byType(FilledButton),
      ),
    );
    expect(filled.onPressed, isNull);
  });

  testWidgets('AppButton.loading shows a disabled progress control', (
    WidgetTester tester,
  ) async {
    await _pump(tester, AppButton.loading());

    expect(find.byType(ProgressRing), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    final button = tester.widget<Button>(
      find.descendant(
        of: find.byType(AppButton),
        matching: find.byType(Button),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('AppButton uses desktop target height, not 48', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      AppButton(label: 'Save', onPressed: () {}),
    );

    final size = tester.getSize(find.byType(AppButton));
    expect(size.height, greaterThanOrEqualTo(AppTargetSize.desktop));
    expect(size.height, lessThan(40));
  });
}
