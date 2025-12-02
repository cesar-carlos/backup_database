import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../application/providers/scheduler_provider.dart';
import '../../domain/entities/schedule.dart';
import '../widgets/common/common.dart';
import '../widgets/schedules/schedules.dart';
import '../widgets/backup/backup_progress_dialog.dart';

class SchedulesPage extends StatefulWidget {
  const SchedulesPage({super.key});

  @override
  State<SchedulesPage> createState() => _SchedulesPageState();
}

class _SchedulesPageState extends State<SchedulesPage> {
  @override
  void initState() {
    super.initState();
    // Carregar agendamentos quando a página é aberta
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SchedulerProvider>().loadSchedules();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Agendamentos',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    context.read<SchedulerProvider>().loadSchedules();
                  },
                  tooltip: 'Atualizar',
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Novo Agendamento',
                  icon: Icons.add,
                  onPressed: () => _showScheduleDialog(context, null),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Consumer<SchedulerProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (provider.error != null) {
                    return AppCard(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              provider.error!,
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => provider.loadSchedules(),
                              child: const Text('Tentar Novamente'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (provider.schedules.isEmpty) {
                    return AppCard(
                      child: EmptyState(
                        icon: Icons.schedule_outlined,
                        message: 'Nenhum agendamento configurado',
                        actionLabel: 'Criar Agendamento',
                        onAction: () => _showScheduleDialog(context, null),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: provider.schedules.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final schedule = provider.schedules[index];
                      return ScheduleListItem(
                        schedule: schedule,
                        onEdit: () => _showScheduleDialog(context, schedule),
                        onDelete: () => _confirmDelete(context, schedule.id),
                        onRunNow: () => _runNow(context, schedule.id),
                        onToggleEnabled: (enabled) =>
                            provider.toggleSchedule(schedule.id, enabled),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showScheduleDialog(
    BuildContext context,
    Schedule? schedule,
  ) async {
    final result = await ScheduleDialog.show(context, schedule: schedule);

    if (result != null && context.mounted) {
      final provider = context.read<SchedulerProvider>();
      final success = schedule == null
          ? await provider.createSchedule(result)
          : await provider.updateSchedule(result);

      if (success && context.mounted) {
        MessageModal.showSuccess(
          context,
          message: schedule == null
              ? 'Agendamento criado com sucesso!'
              : 'Agendamento atualizado com sucesso!',
        );
      } else if (context.mounted) {
        ErrorModal.show(
          context,
          message: provider.error ?? 'Erro ao salvar agendamento',
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text('Tem certeza que deseja excluir este agendamento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.delete,
              foregroundColor: AppColors.buttonTextOnColored,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final provider = context.read<SchedulerProvider>();
      final success = await provider.deleteSchedule(id);

      if (success && context.mounted) {
        MessageModal.showSuccess(
          context,
          message: 'Agendamento excluído com sucesso!',
        );
      } else if (context.mounted) {
        ErrorModal.show(
          context,
          message: provider.error ?? 'Erro ao excluir agendamento',
        );
      }
    }
  }

  Future<void> _runNow(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Executar Backup'),
        content: const Text('Deseja executar este backup agora?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Executar'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final schedulerProvider = context.read<SchedulerProvider>();

      // Mostrar dialog de progresso
      BackupProgressDialog.show(context);

      // Executar backup em background
      final success = await schedulerProvider.executeNow(id);

      // Aguardar um pouco para mostrar o resultado final
      await Future.delayed(const Duration(seconds: 1));

      // Fechar dialog e mostrar resultado
      if (context.mounted) {
        Navigator.of(context).pop(); // Fechar dialog de progresso

        if (success) {
          MessageModal.showSuccess(
            context,
            message: 'Backup executado com sucesso!',
          );
        } else {
          ErrorModal.show(
            context,
            title: 'Erro ao Executar Backup',
            message: schedulerProvider.error ?? 'Erro ao executar backup',
          );
        }
      }
    }
  }
}
