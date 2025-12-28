import 'package:fluent_ui/fluent_ui.dart';

import '../widgets/settings/general_settings_tab.dart';
import '../widgets/settings/license_settings_tab.dart';
import '../widgets/settings/service_settings_tab.dart';

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
      header: const PageHeader(title: Text('Configurações')),
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
                  text: const Text('Geral'),
                  body: const GeneralSettingsTab(),
                ),
                Tab(
                  icon: const Icon(FluentIcons.server),
                  text: const Text('Serviço Windows'),
                  body: const ServiceSettingsTab(),
                ),
                Tab(
                  icon: const Icon(FluentIcons.lock),
                  text: const Text('Licenciamento'),
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
