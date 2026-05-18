import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/presentation/widgets/atoms/app_button.dart';
import 'package:backup_database/presentation/widgets/molecules/password_field.dart';
import 'package:backup_database/presentation/widgets/organisms/message_modal.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

FluentThemeData _a11yFluentTheme() {
  return FluentThemeData.light().copyWith(
    extensions: const [AppSemanticColors.light],
  );
}

void main() {
  testWidgets(
    'atom AppButton meets tap target and text contrast guidelines',
    (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          FluentApp(
            theme: _a11yFluentTheme(),
            locale: const Locale('pt'),
            home: ScaffoldPage(
              content: Center(
                child: AppButton(
                  label: 'Salvar',
                  onPressed: _noop,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'molecule PasswordField meets tap target and text contrast guidelines',
    (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          FluentApp(
            theme: _a11yFluentTheme(),
            locale: const Locale('pt'),
            home: const ScaffoldPage(
              content: Center(
                child: PasswordField(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'organism MessageModal meets tap target and text contrast guidelines',
    (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          FluentApp(
            theme: _a11yFluentTheme(),
            locale: const Locale('pt'),
            home: const ScaffoldPage(
              content: Center(
                child: MessageModal(
                  title: 'Aviso',
                  message: 'Mensagem de teste de acessibilidade.',
                  type: MessageType.info,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      } finally {
        semantics.dispose();
      }
    },
  );
}

void _noop() {}
