import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/dashboard/dashboard_stats_strip.dart';
import 'package:backup_database/presentation/widgets/organisms/app_dialog_shell.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppDialogConstraints clamps to an 800x600 viewport', (
    WidgetTester tester,
  ) async {
    late BoxConstraints constraints;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: Builder(
          builder: (BuildContext context) {
            constraints = AppDialogConstraints.of(
              context,
              preferredWidth: 900,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(constraints.maxWidth, 800 - AppSpacing.xl);
    expect(constraints.maxHeight, 600 * AppDialogConstraints.maxHeightFraction);
  });

  testWidgets('AppDialogShell fits in an 800x600 window without overflow', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(AppBreakpoints.minimumWindow);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        home: AppDialogShell(
          title: const Text('Dialog'),
          content: Column(
            children: [
              for (var i = 0; i < 12; i++) Text('Line $i'),
            ],
          ),
          actions: [
            Button(
              onPressed: () {},
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Dialog'), findsOneWidget);
  });

  testWidgets('DashboardStatsStrip wraps cards in a narrow viewport', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(520, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        home: ScaffoldPage(
          content: SizedBox(
            width: 520,
            child: DashboardStatsStrip(
              children: [
                for (var i = 0; i < 4; i++)
                  ColoredBox(
                    color: const Color(0xFFEEEEEE),
                    child: SizedBox(height: 80, child: Text('Card $i')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Card 0'), findsOneWidget);
    expect(find.text('Card 3'), findsOneWidget);
  });
}
