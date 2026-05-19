import 'package:backup_database/presentation/widgets/organisms/app_section_card.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppSectionCard renders title, description, banner and footer', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: AppSectionCard(
            title: 'Auto update',
            description: 'Operational summary',
            banner: const InfoBar(
              title: Text('Attention'),
              content: Text('Blocked by active backup'),
            ),
            footer: Button(
              onPressed: () {},
              child: const Text('See details'),
            ),
            child: const Text('Main content'),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Auto update'), findsOneWidget);
    expect(find.text('Operational summary'), findsOneWidget);
    expect(find.text('Blocked by active backup'), findsOneWidget);
    expect(find.text('Main content'), findsOneWidget);
    expect(find.text('See details'), findsOneWidget);
  });
}
