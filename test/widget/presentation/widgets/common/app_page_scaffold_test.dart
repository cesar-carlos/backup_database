import 'package:backup_database/presentation/widgets/organisms/app_page_scaffold.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppPageScaffold renders title, actions and body', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: AppPageScaffold(
          title: 'Destinations',
          actions: [
            AppPageAction(label: 'Refresh', icon: FluentIcons.refresh),
            AppPageAction(
              label: 'New destination',
              icon: FluentIcons.add,
              isPrimary: true,
            ),
          ],
          body: Text('Body content'),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Destinations'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('New destination'), findsOneWidget);
    expect(find.text('Body content'), findsOneWidget);
  });

  testWidgets('AppPageScaffold uses custom commandBar when provided', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: AppPageScaffold(
          title: 'Custom bar',
          commandBar: Text('Custom command'),
          body: Text('Body'),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Custom command'), findsOneWidget);
  });

  testWidgets('AppPageScaffold renders icon-only action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: AppPageScaffold(
          title: 'Icon only',
          actions: [
            AppPageAction(
              label: 'Refresh',
              icon: FluentIcons.refresh,
              iconOnly: true,
            ),
          ],
          body: Text('Body'),
        ),
      ),
    );

    await tester.pump();

    expect(find.byIcon(FluentIcons.refresh), findsOneWidget);
    expect(find.text('Refresh'), findsNothing);
  });
}
