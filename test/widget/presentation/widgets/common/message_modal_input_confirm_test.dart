import 'package:backup_database/core/theme/tokens/app_density.dart';
import 'package:backup_database/presentation/providers/app_density_provider.dart';
import 'package:backup_database/presentation/widgets/organisms/message_modal.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  String? result;
  String? lastAction;

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Button(
            child: const Text('open'),
            onPressed: () async {
              final r = await MessageModal.showInputConfirm(
                context,
                title: 'Rename configuration',
                message: 'Enter name.',
                fieldLabel: 'Name',
                initialValue: 'orig (cópia)',
                confirmLabel: 'Duplicate',
                confirmIcon: FluentIcons.copy,
              );
              setState(() {
                result = r;
                lastAction = r == null ? 'cancel' : 'confirm';
              });
            },
          ),
          if (lastAction != null) Text('action:$lastAction'),
          if (result != null) Text('result:$result'),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('showInputConfirm returns trimmed text on confirm', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        locale: Locale('en'),
        home: InheritedAppDensity(
          density: AppDensity.comfortable,
          child: _Harness(),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox), '  NewCfg  ');
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(find.text('action:confirm'), findsOneWidget);
    expect(find.text('result:NewCfg'), findsOneWidget);
  });

  testWidgets('showInputConfirm returns null when cancelled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        locale: Locale('en'),
        home: InheritedAppDensity(
          density: AppDensity.comfortable,
          child: _Harness(),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('action:cancel'), findsOneWidget);
    expect(find.text('result:NewCfg'), findsNothing);
  });
}
