import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/providers/app_density_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_golden_test/widgetbook_golden_test.dart';
import 'package:widgetbook_workspace/main.directories.g.dart';

FluentThemeData _goldenFluentTheme() {
  return FluentThemeData.light().copyWith();
}

FluentThemeData _goldenFluentDarkTheme() {
  return FluentThemeData.dark().copyWith();
}

bool _includeComponent(String componentName) {
  return const {
    'AppDataGrid',
    'DatabaseConfigDataGrid',
    'AppDialogShell',
    'AppButton',
    'AppStatusChip',
    'AppPageScaffold',
    'AppPageState',
    'AppSectionCard',
    'DestinationGrid',
    'AppTextField',
    'PasswordField',
    'ScheduleGrid',
    'MessageModal',
    'EmptyState',
    'SectionHeaderWithStatusBadges',
    'AppCallout',
    'AppIconButton',
    'HostPortFields',
    'LabeledToggle',
  }.contains(componentName);
}

bool _skipUseCase(String componentName, String useCaseName) {
  if (componentName == 'AppTextField' && useCaseName == 'Knobs') {
    return true;
  }
  if (componentName == 'AppButton' && useCaseName == 'Loading') {
    return true;
  }
  return false;
}

WidgetbookNode? _mapNodeForGoldens(WidgetbookNode node) {
  if (node is WidgetbookComponent) {
    final componentName = node.name.split('<').first;
    if (!_includeComponent(componentName)) {
      return null;
    }
    final List<WidgetbookUseCase> cases = node.useCases
        .where((WidgetbookUseCase u) => !_skipUseCase(componentName, u.name))
        .map(
          (u) => WidgetbookUseCase(
            name: u.name,
            builder: (_) => _GoldenUseCaseRoot(builder: u.builder),
          ),
        )
        .toList();
    if (cases.isEmpty) {
      return null;
    }
    return WidgetbookComponent(name: componentName, useCases: cases);
  }
  final List<WidgetbookNode>? children = node.children;
  if (children == null || children.isEmpty) {
    return null;
  }
  final List<WidgetbookNode> mapped = children
      .map(_mapNodeForGoldens)
      .whereType<WidgetbookNode>()
      .toList();
  if (mapped.isEmpty) {
    return null;
  }
  return node.copyWith(children: mapped);
}

// The package renderer finds a use case by its root runtimeType. Common roots
// such as Align also exist in its own app shell, producing blank/wrong images.
// Give every case an unambiguous root and deterministic density.
class _GoldenUseCaseRoot extends StatelessWidget {
  const _GoldenUseCaseRoot({required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => InheritedAppDensity(
    density: AppDensity.comfortable,
    child: FluentTheme(
      data: _goldenFluentTheme(),
      child: Builder(builder: builder),
    ),
  );
}

List<WidgetbookNode> _goldenRoots() {
  return directories
      .map(_mapNodeForGoldens)
      .whereType<WidgetbookNode>()
      .toList();
}

void main() {
  final WidgetbookTheme<FluentThemeData> lightFluent = WidgetbookTheme(
    name: 'Light',
    data: _goldenFluentTheme(),
  );
  final WidgetbookTheme<FluentThemeData> darkFluent = WidgetbookTheme(
    name: 'Dark',
    data: _goldenFluentDarkTheme(),
  );
  final WidgetbookTheme<AppDensity> densityComfortable = WidgetbookTheme(
    name: 'Comfortable',
    data: AppDensity.comfortable,
  );
  final List<Locale> goldenLocales = const [Locale('en', 'US'), Locale('pt')];

  runWidgetbookGoldenTests(
    nodes: _goldenRoots(),
    goldenSnapshotsOutputPath: 'goldens/widgetbook',
    properties: WidgetbookGoldenTestsProperties(
      testGroupName: 'widgetbook use-case goldens',
      addons: [
        LocalizationAddon(
          locales: goldenLocales,
          initialLocale: goldenLocales.first,
          localizationsDelegates: const [
            FluentLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
        ),
        ThemeAddon<FluentThemeData>(
          themes: [lightFluent, darkFluent],
          initialTheme: lightFluent,
          themeBuilder:
              (BuildContext context, FluentThemeData theme, Widget child) {
                return FluentTheme(data: theme, child: child);
              },
        ),
        ThemeAddon<AppDensity>(
          themes: [
            WidgetbookTheme(name: 'Compact', data: AppDensity.compact),
            densityComfortable,
            WidgetbookTheme(name: 'Spacious', data: AppDensity.spacious),
          ],
          initialTheme: densityComfortable,
          themeBuilder:
              (BuildContext context, AppDensity density, Widget child) {
                return InheritedAppDensity(density: density, child: child);
              },
        ),
      ],
    ),
  );
}
