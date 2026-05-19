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
}
