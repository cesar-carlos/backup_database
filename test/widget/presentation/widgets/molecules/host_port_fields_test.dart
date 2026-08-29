import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/presentation/widgets/atoms/app_text_field.dart';
import 'package:backup_database/presentation/widgets/molecules/host_port_fields.dart';
import 'package:backup_database/presentation/widgets/molecules/numeric_field.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HostPortFields renders host and port labels', (
    WidgetTester tester,
  ) async {
    final host = TextEditingController(text: 'localhost');
    final port = TextEditingController(text: '5432');
    addTearDown(host.dispose);
    addTearDown(port.dispose);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        home: ScaffoldPage(
          content: HostPortFields(
            hostController: host,
            portController: port,
            hostLabel: 'Host',
            portLabel: 'Port',
          ),
        ),
      ),
    );

    expect(find.text('Host'), findsOneWidget);
    expect(find.text('Port'), findsOneWidget);
    expect(find.byType(NumericField), findsOneWidget);
    expect(find.byType(AppTextField), findsNWidgets(2));
  });
}
