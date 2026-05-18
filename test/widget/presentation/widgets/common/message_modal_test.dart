import 'package:backup_database/presentation/widgets/organisms/message_modal.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('showConfirm returns false when cancel is tapped', (
    WidgetTester tester,
  ) async {
    bool? result;

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        home: ScaffoldPage(
          content: Builder(
            builder: (BuildContext context) {
              return Button(
                child: const Text('open'),
                onPressed: () async {
                  result = await MessageModal.showConfirm(
                    context,
                    title: 'Title',
                    message: 'Message body',
                    confirmLabel: 'Confirm',
                  );
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('showConfirm returns true when confirm is tapped', (
    WidgetTester tester,
  ) async {
    bool? result;

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        home: ScaffoldPage(
          content: Builder(
            builder: (BuildContext context) {
              return Button(
                child: const Text('open'),
                onPressed: () async {
                  result = await MessageModal.showConfirm(
                    context,
                    title: 'Title',
                    message: 'Message body',
                    confirmLabel: 'Confirm',
                  );
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
