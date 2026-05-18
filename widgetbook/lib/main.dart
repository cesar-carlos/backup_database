import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/providers/app_density_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import 'main.directories.g.dart';

void main() {
  runApp(const WidgetbookApp());
}

Widget _fluentAppBuilder(BuildContext context, Widget child) {
  return FluentApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightFluentTheme,
    darkTheme: AppTheme.darkFluentTheme,
    themeMode: ThemeMode.light,
    home: ScaffoldPage(
      content: Align(
        alignment: Alignment.topCenter,
        child: Padding(padding: AppSpacing.paddingMd, child: child),
      ),
    ),
  );
}

@widgetbook.App()
class WidgetbookApp extends StatelessWidget {
  const WidgetbookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Widgetbook(
      appBuilder: _fluentAppBuilder,
      directories: directories,
      addons: [
        ThemeAddon<FluentThemeData>(
          themes: [
            WidgetbookTheme(name: 'Light', data: AppTheme.lightFluentTheme),
            WidgetbookTheme(name: 'Dark', data: AppTheme.darkFluentTheme),
          ],
          initialTheme: WidgetbookTheme(
            name: 'Light',
            data: AppTheme.lightFluentTheme,
          ),
          themeBuilder:
              (BuildContext context, FluentThemeData theme, Widget child) {
                return FluentTheme(data: theme, child: child);
              },
        ),
        ThemeAddon<AppDensity>(
          themes: [
            WidgetbookTheme(name: 'Compact', data: AppDensity.compact),
            WidgetbookTheme(name: 'Comfortable', data: AppDensity.comfortable),
            WidgetbookTheme(name: 'Spacious', data: AppDensity.spacious),
          ],
          initialTheme: WidgetbookTheme(
            name: 'Comfortable',
            data: AppDensity.comfortable,
          ),
          themeBuilder:
              (BuildContext context, AppDensity density, Widget child) {
                return InheritedAppDensity(density: density, child: child);
              },
        ),
      ],
    );
  }
}
