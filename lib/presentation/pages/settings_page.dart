import 'package:backup_database/core/config/app_mode_policy.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/general_settings_tab.dart';
import 'package:backup_database/presentation/widgets/settings/license_settings_tab.dart';
import 'package:backup_database/presentation/widgets/settings/service_settings_tab.dart';
import 'package:backup_database/presentation/widgets/settings/system_settings_tab.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final showServiceTab = !AppModePolicy.isClient;
    final tabs = <Tab>[
      Tab(
        icon: const Icon(FluentIcons.system),
        text: Text(
          appLocaleString(context, 'Sistema', 'System'),
        ),
        body: const SystemSettingsTab(),
      ),
      Tab(
        icon: const Icon(FluentIcons.settings),
        text: Text(
          appLocaleString(context, 'Atualizacoes', 'Updates'),
        ),
        body: const GeneralSettingsTab(),
      ),
      if (showServiceTab)
        Tab(
          icon: const Icon(FluentIcons.server),
          text: Text(
            appLocaleString(
              context,
              'Serviço Windows',
              'Windows service',
            ),
          ),
          body: const ServiceSettingsTab(),
        ),
      Tab(
        icon: const Icon(FluentIcons.lock),
        text: Text(
          appLocaleString(context, 'Licenciamento', 'Licensing'),
        ),
        body: const LicenseSettingsTab(),
      ),
    ];
    final safeIndex = _selectedTabIndex.clamp(0, tabs.length - 1);

    return AppPageScaffold(
      title: appLocaleString(context, 'Configurações', 'Settings'),
      bodyPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      body: TabView(
        currentIndex: safeIndex,
        onChanged: (index) {
          setState(() {
            _selectedTabIndex = index;
          });
        },
        tabs: tabs,
      ),
    );
  }
}
