import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/presentation/widgets/atoms/app_button.dart';
import 'package:backup_database/presentation/widgets/atoms/app_card.dart';
import 'package:backup_database/presentation/widgets/atoms/app_text_field.dart';
import 'package:backup_database/presentation/widgets/atoms/empty_state.dart';
import 'package:backup_database/presentation/widgets/organisms/message_modal.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

FluentThemeData _goldenFluentTheme() {
  return FluentThemeData.light().copyWith(
    extensions: const [AppSemanticColors.light],
  );
}

Widget _goldenApp({required Widget home}) {
  return FluentApp(
    theme: _goldenFluentTheme(),
    locale: const Locale('pt'),
    home: ScaffoldPage(
      content: Padding(
        padding: const EdgeInsets.all(24),
        child: RepaintBoundary(
          key: const Key('golden_surface'),
          child: Align(
            alignment: Alignment.topLeft,
            child: home,
          ),
        ),
      ),
    ),
  );
}

void main() {
  const surfaceSize = Size(520, 420);

  Future<void> pumpGolden(
    WidgetTester tester, {
    required String goldenName,
    required Widget subject,
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_goldenApp(home: subject));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('golden_surface')),
      matchesGoldenFile('goldens/$goldenName.png'),
    );
  }

  testWidgets('AppCard', (WidgetTester tester) async {
    await pumpGolden(
      tester,
      goldenName: 'design_system_app_card',
      subject: const AppCard(
        child: Text('Card content'),
      ),
    );
  });

  testWidgets('AppButton', (WidgetTester tester) async {
    await pumpGolden(
      tester,
      goldenName: 'design_system_app_button',
      subject: AppButton(
        label: 'Continuar',
        onPressed: () {},
      ),
    );
  });

  testWidgets('AppTextField', (WidgetTester tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpGolden(
      tester,
      goldenName: 'design_system_app_text_field',
      subject: AppTextField(
        label: 'Nome',
        hint: 'Opcional',
        controller: controller,
        validator: (String? value) =>
            (value == null || value.isEmpty) ? 'Obrigatório' : null,
      ),
    );
  });

  testWidgets('MessageModal', (WidgetTester tester) async {
    await pumpGolden(
      tester,
      goldenName: 'design_system_message_modal',
      subject: const MessageModal(
        title: 'Título',
        message: 'Corpo da mensagem para golden.',
        type: MessageType.info,
      ),
    );
  });

  testWidgets('EmptyState', (WidgetTester tester) async {
    await pumpGolden(
      tester,
      goldenName: 'design_system_empty_state',
      subject: const EmptyState(
        message: 'Nada aqui',
        icon: FluentIcons.inbox,
      ),
    );
  });
}
