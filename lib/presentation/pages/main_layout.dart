import 'package:backup_database/application/providers/dashboard_provider.dart';
import 'package:backup_database/application/providers/destination_provider.dart';
import 'package:backup_database/application/providers/log_provider.dart';
import 'package:backup_database/application/providers/remote_file_transfer_provider.dart';
import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/application/providers/scheduler_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/application/providers/server_credential_provider.dart';
import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/core/theme/theme_provider.dart';
import 'package:backup_database/presentation/widgets/navigation/navigation_item.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({required this.child, super.key});
  final Widget child;

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  List<NavigationItem> get _navigationItems {
    final mode = currentAppMode;

    final allItems = [
      const NavigationItem(
        icon: FluentIcons.view_dashboard,
        selectedIcon: FluentIcons.view_dashboard,
        label: 'Dashboard',
        route: RouteNames.dashboard,
      ),
      const NavigationItem(
        icon: FluentIcons.database,
        selectedIcon: FluentIcons.database,
        label: 'Bancos de Dados',
        route: RouteNames.sqlServerConfig,
      ),
      const NavigationItem(
        icon: FluentIcons.folder,
        selectedIcon: FluentIcons.folder,
        label: 'Destinos',
        route: RouteNames.destinations,
      ),
      const NavigationItem(
        icon: FluentIcons.calendar,
        selectedIcon: FluentIcons.calendar,
        label: 'Agendamentos',
        route: RouteNames.schedules,
      ),
      const NavigationItem(
        icon: FluentIcons.server,
        selectedIcon: FluentIcons.server,
        label: 'Servidor',
        route: RouteNames.serverSettings,
      ),
      const NavigationItem(
        icon: FluentIcons.plug,
        selectedIcon: FluentIcons.plug,
        label: 'Conectar',
        route: RouteNames.serverLogin,
      ),
      const NavigationItem(
        icon: FluentIcons.calendar_agenda,
        selectedIcon: FluentIcons.calendar_agenda,
        label: 'Agendamentos Remotos',
        route: RouteNames.remoteSchedules,
      ),
      const NavigationItem(
        icon: FluentIcons.download,
        selectedIcon: FluentIcons.download,
        label: 'Transferir Backups',
        route: RouteNames.transferBackups,
      ),
      const NavigationItem(
        icon: FluentIcons.megaphone,
        selectedIcon: FluentIcons.megaphone,
        label: 'Notificações',
        route: RouteNames.notifications,
      ),
      const NavigationItem(
        icon: FluentIcons.document,
        selectedIcon: FluentIcons.document,
        label: 'Logs',
        route: RouteNames.logs,
      ),
      const NavigationItem(
        icon: FluentIcons.settings,
        selectedIcon: FluentIcons.settings,
        label: 'Configurações',
        route: RouteNames.settings,
      ),
    ];

    // Filtrar itens baseado no modo
    switch (mode) {
      case AppMode.client:
        // Cliente NÃO vê: Bancos de Dados, Agendamentos, Servidor, Logs, Notificações
        // Cliente apenas se conecta ao servidor e executa ações remotas
        return allItems
            .where(
              (item) =>
                  item.route != RouteNames.sqlServerConfig &&
                  item.route != RouteNames.schedules &&
                  item.route != RouteNames.serverSettings &&
                  item.route != RouteNames.logs &&
                  item.route != RouteNames.notifications,
            )
            .toList();

      case AppMode.server:
        // Servidor NÃO vê: Conectar, Agendamentos Remotos, Transferir Backups
        return allItems
            .where(
              (item) =>
                  item.route != RouteNames.serverLogin &&
                  item.route != RouteNames.remoteSchedules &&
                  item.route != RouteNames.transferBackups,
            )
            .toList();

      case AppMode.unified:
        // Não usado mais (apenas server e client)
        return allItems;
    }
  }

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
      case RouteNames.sqlServerConfig:
      case RouteNames.sybaseConfig:
        context.read<SqlServerConfigProvider>().loadConfigs();
      case RouteNames.destinations:
        context.read<DestinationProvider>().loadDestinations();
      case RouteNames.schedules:
        context.read<SchedulerProvider>().loadSchedules();
      case RouteNames.logs:
        context.read<LogProvider>().refresh();
      case RouteNames.notifications:
      case RouteNames.settings:
        break;
      case RouteNames.serverSettings:
        context.read<ServerCredentialProvider>().loadCredentials();
      case RouteNames.serverLogin:
        context.read<ServerConnectionProvider>().loadConnections();
      case RouteNames.remoteSchedules:
        if (context.read<ServerConnectionProvider>().isConnected) {
          context.read<RemoteSchedulesProvider>().loadSchedules();
        }
      case RouteNames.transferBackups:
        if (context.read<ServerConnectionProvider>().isConnected) {
          context.read<RemoteFileTransferProvider>().loadAvailableFiles();
        }
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
        children: _navigationItems.asMap().entries.map(
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
        ).toList(),
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
              onPressed: themeProvider.toggleTheme,
            ),
          ),
        ],
      ),
    );
  }
}
