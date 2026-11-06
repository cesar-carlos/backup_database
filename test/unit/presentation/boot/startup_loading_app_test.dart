import 'package:backup_database/presentation/boot/startup_loading_app.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders startup feedback without initialized providers', (
    tester,
  ) async {
    await tester.pumpWidget(const StartupLoadingApp());
    expect(find.text('Inicializando Backup Database…'), findsOneWidget);
    expect(find.byType(ProgressRing), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
