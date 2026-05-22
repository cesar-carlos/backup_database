import 'dart:async';
import 'dart:convert';

import 'package:backup_database/application/providers/dashboard_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/constants/app_image_assets.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/schedule_config.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/dashboard/dashboard.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const double _dashboardStatsCardWidth = 280;

  static const String _dashboardStatIconAsset = AppImageAssets.database128;

  String? _selectedConnectionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<DashboardProvider>().loadDashboardData());
    });
  }

  @override
  Widget build(BuildContext context) {
    final isClientMode = currentAppMode == AppMode.client;

    return ScaffoldPage(
      header: const PageHeader(title: Text('Painel')),
      content: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Server selector (Client Mode only)
            if (isClientMode)
              Consumer<ServerConnectionProvider>(
                builder: (context, connProvider, child) {
                  final connections = connProvider.connections;

                  if (connections.isEmpty) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: EmptyState(
                        icon: FluentIcons.server,
                        message: appLocaleString(
                          context,
                          'Nenhum servidor salvo. Adicione uma conexão para '
                              'ver métricas remotas.',
                          'No saved servers. Add a connection to see remote '
                              'metrics.',
                        ),
                        actionLabel: appLocaleString(
                          context,
                          'Conectar',
                          'Connect',
                        ),
                        onAction: () => context.go(RouteNames.serverLogin),
                      ),
                    );
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Servidor Remoto',
                            style: FluentTheme.of(context).typography.subtitle,
                          ),
                          const SizedBox(height: 4),
                          ComboBox<String>(
                            placeholder: const Text('Selecione um servidor'),
                            isExpanded: true,
                            items: connections
                                .map(
                                  (conn) => ComboBoxItem<String>(
                                    value: conn.id,
                                    child: Text(conn.name),
                                  ),
                                )
                                .toList(),
                            value: _selectedConnectionId,
                            onChanged: (value) async {
                              if (value == null) return;
                              setState(() => _selectedConnectionId = value);

                              // Connect to selected server
                              await connProvider.connectTo(value);

                              // Refresh dashboard metrics
                              if (!context.mounted) return;
                              unawaited(
                                context.read<DashboardProvider>().refresh(),
                              );
                            },
                          ),
                          if (connProvider.isConnecting)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: ProgressRing(),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            if (isClientMode)
              Consumer<ServerConnectionProvider>(
                builder: (context, connProvider, _) {
                  final health = connProvider.serverHealth;
                  if (!connProvider.isConnected ||
                      health == null ||
                      health.isOk) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: InfoBar(
                      title: Text(
                        appLocaleString(
                          context,
                          'Servidor com problemas',
                          'Server degraded',
                        ),
                      ),
                      content: SelectableText(
                        health.message ??
                            appLocaleString(
                              context,
                              'Verifique o servidor antes de executar backups.',
                              'Check the server before running backups.',
                            ),
                      ),
                      severity: health.isUnhealthy
                          ? InfoBarSeverity.error
                          : InfoBarSeverity.warning,
                      isLong: true,
                    ),
                  );
                },
              ),
            if (isClientMode)
              Consumer<ServerConnectionProvider>(
                builder: (context, connProvider, _) {
                  if (connProvider.isConnected ||
                      connProvider.connections.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: InfoBar(
                      title: Text(
                        appLocaleString(
                          context,
                          'Desconectado',
                          'Disconnected',
                        ),
                      ),
                      content: Text(
                        appLocaleString(
                          context,
                          'Conecte-se a um servidor para ver métricas em tempo real.',
                          'Connect to a server to see live metrics.',
                        ),
                      ),
                      severity: InfoBarSeverity.warning,
                      action: Button(
                        onPressed: () => context.go(RouteNames.serverLogin),
                        child: Text(
                          appLocaleString(context, 'Conectar', 'Connect'),
                        ),
                      ),
                    ),
                  );
                },
              ),
            Consumer<DashboardProvider>(
              builder: (context, provider, child) {
                final loadError = provider.error;
                if (loadError != null && loadError.trim().isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: InfoBar(
                      title: Text(
                        appLocaleString(
                          context,
                          'Erro ao carregar o painel',
                          'Failed to load dashboard',
                        ),
                      ),
                      content: SelectableText.rich(
                        TextSpan(
                          text: loadError,
                          style: FluentTheme.of(context).typography.body
                              ?.copyWith(
                                color: context.colors.danger,
                              ),
                        ),
                      ),
                      severity: InfoBarSeverity.error,
                      action: Button(
                        onPressed: () =>
                            unawaited(provider.loadDashboardData()),
                        child: Text(
                          appLocaleString(
                            context,
                            'Tentar novamente',
                            'Try again',
                          ),
                        ),
                      ),
                    ),
                  );
                }

                if (provider.isLoading && provider.totalBackups == 0) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: SkeletonDashboardMetrics(),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Show "Local" only in Server/Unified mode
                    if (!isClientMode)
                      Text(
                        'Local',
                        style: FluentTheme.of(context).typography.subtitle,
                      ),
                    if (!isClientMode) const SizedBox(height: 4),
                    if (!isClientMode)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: _dashboardStatsCardWidth,
                              child: StatsCard(
                                title: 'Total de Backups',
                                value: provider.totalBackups.toString(),
                                iconAsset: _dashboardStatIconAsset,
                                color: AppPalette.primary,
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: _dashboardStatsCardWidth,
                              child: StatsCard(
                                title: 'Backups Hoje',
                                value: provider.backupsToday.toString(),
                                iconAsset: _dashboardStatIconAsset,
                                color: AppPalette.statsBackups,
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: _dashboardStatsCardWidth,
                              child: StatsCard(
                                title: 'Falharam Hoje',
                                value: provider.failedToday.toString(),
                                iconAsset: _dashboardStatIconAsset,
                                color: AppPalette.statsFailed,
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: _dashboardStatsCardWidth,
                              child: StatsCard(
                                title: 'Agendamentos Ativos',
                                value: provider.activeSchedules.toString(),
                                iconAsset: _dashboardStatIconAsset,
                                color: AppPalette.statsActive,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (provider.serverMetrics != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        isClientMode ? 'Servidor Remoto' : 'Servidor',
                        style: FluentTheme.of(context).typography.subtitle,
                      ),
                      const SizedBox(height: 4),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: _dashboardStatsCardWidth,
                              child: StatsCard(
                                title: 'Total de Backups (Servidor)',
                                value: _serverMetric(
                                  provider.serverMetrics!,
                                  'totalBackups',
                                ),
                                iconAsset: _dashboardStatIconAsset,
                                color: AppPalette.primary,
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: _dashboardStatsCardWidth,
                              child: StatsCard(
                                title: 'Backups Hoje (Servidor)',
                                value: _serverMetric(
                                  provider.serverMetrics!,
                                  'backupsToday',
                                ),
                                iconAsset: _dashboardStatIconAsset,
                                color: AppPalette.statsBackups,
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: _dashboardStatsCardWidth,
                              child: StatsCard(
                                title: 'Falharam Hoje (Servidor)',
                                value: _serverMetric(
                                  provider.serverMetrics!,
                                  'failedToday',
                                ),
                                iconAsset: _dashboardStatIconAsset,
                                color: AppPalette.statsFailed,
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: _dashboardStatsCardWidth,
                              child: StatsCard(
                                title: 'Agendamentos Ativos (Servidor)',
                                value: _serverMetric(
                                  provider.serverMetrics!,
                                  'activeSchedules',
                                ),
                                iconAsset: _dashboardStatIconAsset,
                                color: AppPalette.statsActive,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (!isClientMode && provider.metricsReport != null) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: MetricsPercentilesCard(
                          report: provider.metricsReport!,
                        ),
                      ),
                    ],
                    // Show local schedules only in Server/Unified mode
                    if (!isClientMode) ...[
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Backups Recentes',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: FluentTheme.of(context).typography.title,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(FluentIcons.refresh),
                            onPressed: () {
                              unawaited(provider.refresh());
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      AppCard(
                        child: RecentBackupsList(
                          backups: provider.recentBackups,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Agendamentos Ativos',
                        style: FluentTheme.of(context).typography.title,
                      ),
                      const SizedBox(height: 16),
                      AppCard(
                        child: provider.activeSchedulesList.isEmpty
                            ? const EmptyState(
                                icon: FluentIcons.calendar,
                                message: 'Nenhum agendamento configurado',
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: provider.activeSchedulesList.length,
                                itemBuilder: (context, index) {
                                  final schedule =
                                      provider.activeSchedulesList[index];
                                  return ListTile(
                                    leading: const Icon(FluentIcons.calendar),
                                    title: Text(schedule.name),
                                    subtitle: Text(
                                      _getScheduleDescription(schedule),
                                    ),
                                    trailing: schedule.enabled
                                        ? Icon(
                                            FluentIcons.check_mark,
                                            color: context.colors.success,
                                          )
                                        : Icon(
                                            FluentIcons.cancel,
                                            color: context.colors.disabled,
                                          ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _serverMetric(Map<String, dynamic> metrics, String key) {
    final value = metrics[key];
    if (value == null) return '0';
    if (value is int) return value.toString();
    return value.toString();
  }

  String _getScheduleDescription(Schedule schedule) {
    switch (scheduleTypeFromString(schedule.scheduleType)) {
      case ScheduleType.daily:
        final config = DailyScheduleConfig.fromJson(
          jsonDecode(schedule.scheduleConfig) as Map<String, dynamic>,
        );
        return 'Diário às ${config.hour.toString().padLeft(2, '0')}:${config.minute.toString().padLeft(2, '0')}';
      case ScheduleType.weekly:
        final config = WeeklyScheduleConfig.fromJson(
          jsonDecode(schedule.scheduleConfig) as Map<String, dynamic>,
        );
        final days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
        final dayNames = config.daysOfWeek.map((d) => days[d - 1]).join(', ');
        return 'Semanal: $dayNames às ${config.hour.toString().padLeft(2, '0')}:${config.minute.toString().padLeft(2, '0')}';
      case ScheduleType.monthly:
        final config = MonthlyScheduleConfig.fromJson(
          jsonDecode(schedule.scheduleConfig) as Map<String, dynamic>,
        );
        final days = config.daysOfMonth.join(', ');
        return 'Mensal: dias $days às ${config.hour.toString().padLeft(2, '0')}:${config.minute.toString().padLeft(2, '0')}';
      case ScheduleType.interval:
        final config = IntervalScheduleConfig.fromJson(
          jsonDecode(schedule.scheduleConfig) as Map<String, dynamic>,
        );
        final hours = config.intervalMinutes ~/ 60;
        final minutes = config.intervalMinutes % 60;
        if (hours > 0) {
          return 'A cada ${hours}h ${minutes}min';
        }
        return 'A cada ${minutes}min';
    }
  }
}
