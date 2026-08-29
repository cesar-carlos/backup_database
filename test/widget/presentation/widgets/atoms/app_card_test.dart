import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/presentation/widgets/atoms/app_card.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

FluentThemeData _theme() {
  return FluentThemeData.light().copyWith(
    extensions: const [AppSemanticColors.light],
  );
}

void main() {
  testWidgets('AppCard is flat and does not paint a drop shadow', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: _theme(),
        home: const ScaffoldPage(
          content: Center(
            child: AppCard(child: Text('Card content')),
          ),
        ),
      ),
    );

    expect(find.byType(Card), findsOneWidget);
    expect(find.byType(HoverButton), findsNothing);

    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((Container container) => container.decoration)
        .whereType<BoxDecoration>();
    for (final decoration in decorations) {
      expect(decoration.boxShadow ?? const <BoxShadow>[], isEmpty);
    }
  });

  testWidgets(
    'AppCard with onTap is keyboard-focusable via HoverButton',
    (
      WidgetTester tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        FluentApp(
          theme: _theme(),
          home: ScaffoldPage(
            content: Center(
              child: AppCard(
                onTap: () => tapped = true,
                child: const Text('Tappable'),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(HoverButton), findsOneWidget);
      await tester.tap(find.text('Tappable'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    },
  );
}
