import 'dart:convert';

import 'package:backup_database/application/providers/dashboard_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/external/scheduler/cron_parser.dart';
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
  String? _selectedConnectionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().loadDashboardData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isClientMode = currentAppMode == AppMode.client;

    return ScaffoldPage(
      header: const PageHeader(title: Text('Painel')),
      content: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Server selector (Client Mode only)
            if (isClientMode)
              Consumer<ServerConnectionProvider>(
                builder: (context, connProvider, child) {
                  final connections = connProvider.connections;

                  if (connections.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 24),
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
                              context.read<DashboardProvider>().refresh();
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
                  if (connProvider.isConnected) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: InfoBar(
                      title: const Text('Desconectado'),
                      content: const Text(
                        'Conecte-se a um servidor para ver métricas em tempo real.',
                      ),
                      severity: InfoBarSeverity.warning,
                      action: Button(
                        onPressed: () => context.go('/server-login'),
                        child: const Text('Conectar'),
                      ),
                    ),
                  );
                },
              ),
            Consumer<DashboardProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.totalBackups == 0) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(48),
                      child: ProgressRing(),
                    ),
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
                      Row(
                        children: [
                          Expanded(
                            child: StatsCard(
                              title: 'Total de Backups',
                              value: provider.totalBackups.toString(),
                              iconSvg: 'assets/icons/icon-512-embedded.svg',
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: StatsCard(
                              title: 'Backups Hoje',
                              value: provider.backupsToday.toString(),
                              icon: FluentIcons.calendar_day,
                              color: AppColors.statsBackups,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: StatsCard(
                              title: 'Falharam Hoje',
                              value: provider.failedToday.toString(),
                              icon: FluentIcons.error,
                              color: AppColors.statsFailed,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: StatsCard(
                              title: 'Agendamentos Ativos',
                              value: provider.activeSchedules.toString(),
                              icon: FluentIcons.calendar,
                              color: AppColors.statsActive,
                            ),
                          ),
                        ],
                      ),
                    if (provider.serverMetrics != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        isClientMode ? 'Servidor Remoto' : 'Servidor',
                        style: FluentTheme.of(context).typography.subtitle,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: StatsCard(
                              title: 'Total de Backups (Servidor)',
                              value: _serverMetric(
                                provider.serverMetrics!,
                                'totalBackups',
                              ),
                              icon: FluentIcons.server,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: StatsCard(
                              title: 'Backups Hoje (Servidor)',
                              value: _serverMetric(
                                provider.serverMetrics!,
                                'backupsToday',
                              ),
                              icon: FluentIcons.calendar_day,
                              color: AppColors.statsBackups,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: StatsCard(
                              title: 'Falharam Hoje (Servidor)',
                              value: _serverMetric(
                                provider.serverMetrics!,
                                'failedToday',
                              ),
                              icon: FluentIcons.error,
                              color: AppColors.statsFailed,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: StatsCard(
                              title: 'Agendamentos Ativos (Servidor)',
                              value: _serverMetric(
                                provider.serverMetrics!,
                                'activeSchedules',
                              ),
                              icon: FluentIcons.calendar,
                              color: AppColors.statsActive,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Show local schedules only in Server/Unified mode
                    if (!isClientMode) ...[
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Backups Recentes',
                            style: FluentTheme.of(context).typography.title,
                          ),
                          IconButton(
                            icon: const Icon(FluentIcons.refresh),
                            onPressed: () {
                              provider.refresh();
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
                                        ? const Icon(
                                            FluentIcons.check_mark,
                                            color: AppColors.success,
                                          )
                                        : const Icon(
                                            FluentIcons.cancel,
                                            color: AppColors.grey600,
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
