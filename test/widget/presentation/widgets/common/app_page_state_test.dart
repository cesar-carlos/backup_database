import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppPageState.error renders message and action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        home: ScaffoldPage(
          content: AppPageState.error(
            title: 'Falha ao carregar',
            message: 'Erro de rede',
            actionLabel: 'Tentar novamente',
            onAction: () {},
          ),
        ),
      ),
    );

    expect(find.text('Falha ao carregar'), findsOneWidget);
    expect(find.text('Erro de rede'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });
}
