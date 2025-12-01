import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/providers/dashboard_provider.dart';
import '../../domain/entities/schedule.dart';
import '../widgets/common/common.dart';
import '../widgets/dashboard/dashboard.dart';

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
    return SingleChildScrollView(
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
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats Cards
                  Row(
                    children: [
                      Expanded(
                        child: StatsCard(
                          title: 'Total de Backups',
                          value: provider.totalBackups.toString(),
                          iconSvg: 'assets/icons/icon-512-embedded.svg',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StatsCard(
                          title: 'Backups Hoje',
                          value: provider.backupsToday.toString(),
                          icon: Icons.today,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StatsCard(
                          title: 'Falharam Hoje',
                          value: provider.failedToday.toString(),
                          icon: Icons.error_outline,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StatsCard(
                          title: 'Agendamentos Ativos',
                          value: provider.activeSchedules.toString(),
                          icon: Icons.schedule,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Recent Backups
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Backups Recentes',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          provider.refresh();
                        },
                        tooltip: 'Atualizar',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    child: RecentBackupsList(backups: provider.recentBackups),
                  ),
                  const SizedBox(height: 32),

                  // Active Schedules
                  Text(
                    'Agendamentos Ativos',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    child: provider.activeSchedulesList.isEmpty
                        ? const EmptyState(
                            icon: Icons.schedule_outlined,
                            message: 'Nenhum agendamento configurado',
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: provider.activeSchedulesList.length,
                            itemBuilder: (context, index) {
                              final schedule = provider.activeSchedulesList[index];
                              return ListTile(
                                leading: const Icon(Icons.schedule),
                                title: Text(schedule.name),
                                subtitle: Text(
                                  _getScheduleDescription(schedule),
                                ),
                                trailing: schedule.enabled
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                      )
                                    : const Icon(
                                        Icons.cancel,
                                        color: Colors.grey,
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
