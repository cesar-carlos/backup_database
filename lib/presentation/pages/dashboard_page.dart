import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../application/providers/dashboard_provider.dart';
import '../../domain/entities/schedule.dart';
import '../widgets/dashboard/dashboard.dart';
import '../widgets/common/common.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().loadDashboardData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('Dashboard')),
      content: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Consumer<DashboardProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.totalBackups == 0) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(48.0),
                      child: ProgressRing(),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      child: RecentBackupsList(backups: provider.recentBackups),
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
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getScheduleDescription(Schedule schedule) {
    switch (schedule.scheduleType) {
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
