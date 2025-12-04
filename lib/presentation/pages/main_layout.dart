import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../application/providers/dashboard_provider.dart';
import '../../application/providers/destination_provider.dart';
import '../../application/providers/log_provider.dart';
import '../../application/providers/scheduler_provider.dart';
import '../../application/providers/sql_server_config_provider.dart';
import '../../core/constants/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_provider.dart';
import '../widgets/navigation/navigation_item.dart';

class MainLayout extends StatefulWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  final List<NavigationItem> _navigationItems = [
    NavigationItem(
      icon: FluentIcons.view_dashboard,
      selectedIcon: FluentIcons.view_dashboard,
      label: 'Dashboard',
      route: RouteNames.dashboard,
    ),
    NavigationItem(
      icon: FluentIcons.database,
      selectedIcon: FluentIcons.database,
      label: 'Bancos de Dados',
      route: RouteNames.sqlServerConfig,
    ),
    NavigationItem(
      icon: FluentIcons.folder,
      selectedIcon: FluentIcons.folder,
      label: 'Destinos',
      route: RouteNames.destinations,
    ),
    NavigationItem(
      icon: FluentIcons.calendar,
      selectedIcon: FluentIcons.calendar,
      label: 'Agendamentos',
      route: RouteNames.schedules,
    ),
    NavigationItem(
      icon: FluentIcons.document,
      selectedIcon: FluentIcons.document,
      label: 'Logs',
      route: RouteNames.logs,
    ),
    NavigationItem(
      icon: FluentIcons.megaphone,
      selectedIcon: FluentIcons.megaphone,
      label: 'Notificações',
      route: RouteNames.notifications,
    ),
    NavigationItem(
      icon: FluentIcons.settings,
      selectedIcon: FluentIcons.settings,
      label: 'Configurações',
      route: RouteNames.settings,
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSelectedIndex();
  }

  void _updateSelectedIndex() {
    final location = GoRouterState.of(context).uri.path;
    final index = _navigationItems.indexWhere((item) => item.route == location);
    if (index >= 0 && index != _selectedIndex) {
      setState(() => _selectedIndex = index);
    }
  }

  void _handleRefresh() {
    final location = GoRouterState.of(context).uri.path;

    switch (location) {
      case RouteNames.dashboard:
        context.read<DashboardProvider>().refresh();
        break;
      case RouteNames.sqlServerConfig:
      case RouteNames.sybaseConfig:
        context.read<SqlServerConfigProvider>().loadConfigs();
        break;
      case RouteNames.destinations:
        context.read<DestinationProvider>().loadDestinations();
        break;
      case RouteNames.schedules:
        context.read<SchedulerProvider>().loadSchedules();
        break;
      case RouteNames.logs:
        context.read<LogProvider>().refresh();
        break;
      case RouteNames.notifications:
      case RouteNames.settings:
        break;
    }
  }

  void _onDestinationSelected(int index) {
    setState(() => _selectedIndex = index);
    context.go(_navigationItems[index].route);
  }

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      content: Row(
        children: [
          _buildNavigationPane(),
          Expanded(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationPane() {
    return Container(
      width: 200,
      color: FluentTheme.of(context).scaffoldBackgroundColor,
      child: ListView(
        children: _navigationItems
            .asMap()
            .entries
            .map(
              (entry) {
                final index = entry.key;
                final item = entry.value;
                final isSelected = index == _selectedIndex;
                return ListTile(
                  leading: Icon(
                    item.icon,
                    color: isSelected
                        ? AppColors.primary
                        : FluentTheme.of(context).resources.textFillColorSecondary,
                  ),
                  title: Text(item.label),
                  onPressed: () => _onDestinationSelected(index),
                );
              },
            )
            .toList(),
      ),
    );
  }

  Widget _buildAppBar() {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: FluentTheme.of(context).resources.controlStrokeColorDefault,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            _navigationItems[_selectedIndex].label,
            style: FluentTheme.of(context).typography.title,
          ),
          const Spacer(),
          Tooltip(
            message: 'Atualizar',
            child: IconButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: _handleRefresh,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Alternar tema',
            child: IconButton(
              icon: Icon(
                themeProvider.isDarkMode
                    ? FluentIcons.brightness
                    : FluentIcons.brightness,
              ),
              onPressed: () {
                themeProvider.toggleTheme();
              },
            ),
          ),
        ],
      ),
    );
  }
}
