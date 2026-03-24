import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/presentation/widgets/settings/general_settings_tab.dart';
import 'package:backup_database/presentation/widgets/settings/license_settings_tab.dart';
import 'package:backup_database/presentation/widgets/settings/service_settings_tab.dart';
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
    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          appLocaleString(context, 'Configurações', 'Settings'),
        ),
      ),
      content: Column(
        children: [
          Expanded(
            child: TabView(
              currentIndex: _selectedTabIndex,
              onChanged: (index) {
                setState(() {
                  _selectedTabIndex = index;
                });
              },
              tabs: [
                Tab(
                  icon: const Icon(FluentIcons.settings),
                  text: Text(
                    appLocaleString(context, 'Geral', 'General'),
                  ),
                  body: const GeneralSettingsTab(),
                ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
