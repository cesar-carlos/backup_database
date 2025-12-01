import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../application/providers/dashboard_provider.dart';
import '../../application/providers/destination_provider.dart';
import '../../application/providers/log_provider.dart';
import '../../application/providers/scheduler_provider.dart';
import '../../application/providers/sql_server_config_provider.dart';
import '../../core/constants/route_names.dart';
import '../../core/theme/theme_provider.dart';
import '../widgets/navigation/navigation.dart';

class MainLayout extends StatefulWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  final List<NavigationItem> _navigationItems = [
    const NavigationItem(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: 'Dashboard',
      route: RouteNames.dashboard,
    ),
    const NavigationItem(
      icon: Icons.storage_outlined,
      selectedIcon: Icons.storage,
      label: 'Bancos de Dados',
      route: RouteNames.sqlServerConfig,
    ),
    const NavigationItem(
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder,
      label: 'Destinos',
      route: RouteNames.destinations,
    ),
    const NavigationItem(
      icon: Icons.schedule_outlined,
      selectedIcon: Icons.schedule,
      label: 'Agendamentos',
      route: RouteNames.schedules,
    ),
    const NavigationItem(
      icon: Icons.article_outlined,
      selectedIcon: Icons.article,
      label: 'Logs',
      route: RouteNames.logs,
    ),
    const NavigationItem(
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications,
      label: 'Notificações',
      route: RouteNames.notifications,
    ),
    const NavigationItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
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
        // Essas páginas não têm refresh específico
        break;
    }
  }

  void _onDestinationSelected(int index) {
    setState(() => _selectedIndex = index);
    context.go(_navigationItems[index].route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SideNavigation(
            items: _navigationItems,
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onDestinationSelected,
          ),
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

  Widget _buildAppBar() {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Text(
            _navigationItems[_selectedIndex].label,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _handleRefresh,
            tooltip: 'Atualizar',
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              themeProvider.isDarkMode
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            onPressed: () {
              themeProvider.toggleTheme();
            },
            tooltip: 'Alternar tema',
          ),
        ],
      ),
    );
  }
}
