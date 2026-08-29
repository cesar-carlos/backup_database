import 'package:backup_database/core/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Fluent dialog theme is flat without drop shadow', (
    WidgetTester tester,
  ) async {
    late ContentDialogThemeData dialogTheme;

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        home: Builder(
          builder: (BuildContext context) {
            dialogTheme = ContentDialogTheme.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final decoration = dialogTheme.decoration;
    expect(decoration, isA<BoxDecoration>());
    final box = decoration! as BoxDecoration;
    expect(box.boxShadow ?? const <BoxShadow>[], isEmpty);
  });
}
