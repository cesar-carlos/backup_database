import 'package:backup_database/presentation/widgets/molecules/section_header_with_status_badges.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows active and inactive badges in English', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        locale: Locale('en'),
        home: ScaffoldPage(
          content: SectionHeaderWithStatusBadges(
            label: 'PostgreSQL',
            count: 3,
            activeCount: 2,
            inactiveCount: 1,
          ),
        ),
      ),
    );

    expect(find.text('PostgreSQL'), findsOneWidget);
    expect(find.text('(3)'), findsOneWidget);
    expect(find.text('2 active'), findsOneWidget);
    expect(find.text('1 inactive'), findsOneWidget);
  });

  testWidgets('uses singular English labels', (WidgetTester tester) async {
    await tester.pumpWidget(
      const FluentApp(
        locale: Locale('en'),
        home: ScaffoldPage(
          content: SectionHeaderWithStatusBadges(
            label: 'SQL Server',
            count: 2,
            activeCount: 1,
            inactiveCount: 1,
          ),
        ),
      ),
    );

    expect(find.text('1 active'), findsOneWidget);
    expect(find.text('1 inactive'), findsOneWidget);
  });

  testWidgets('omits badge when count is zero', (WidgetTester tester) async {
    await tester.pumpWidget(
      const FluentApp(
        locale: Locale('en'),
        home: ScaffoldPage(
          content: SectionHeaderWithStatusBadges(
            label: 'Sybase',
            count: 1,
            activeCount: 1,
            inactiveCount: 0,
          ),
        ),
      ),
    );

    expect(find.text('1 active'), findsOneWidget);
    expect(find.textContaining('inactive'), findsNothing);
  });

  testWidgets('shows Portuguese plural labels', (WidgetTester tester) async {
    await tester.pumpWidget(
      const FluentApp(
        locale: Locale('pt'),
        home: ScaffoldPage(
          content: SectionHeaderWithStatusBadges(
            label: 'PostgreSQL',
            count: 4,
            activeCount: 3,
            inactiveCount: 1,
          ),
        ),
      ),
    );

    expect(find.text('3 ativas'), findsOneWidget);
    expect(find.text('1 inativa'), findsOneWidget);
  });
}
