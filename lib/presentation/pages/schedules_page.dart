import 'package:backup_database/application/providers/scheduler_provider.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/backup/backup_progress_dialog.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/schedules/schedules.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class SchedulesPage extends StatefulWidget {
  const SchedulesPage({super.key});

  @override
  State<SchedulesPage> createState() => _SchedulesPageState();
}

class _SchedulesPageState extends State<SchedulesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SchedulerProvider>().loadSchedules();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Agendamentos'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: () {
                context.read<SchedulerProvider>().loadSchedules();
              },
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('Novo Agendamento'),
              onPressed: () => _showScheduleDialog(context, null),
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Consumer<SchedulerProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading) {
                    return const Center(child: ProgressRing());
                  }

                  if (provider.error != null) {
                    return AppCard(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                FluentIcons.error,
                                size: 64,
                                color: AppColors.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                provider.error!,
                                style: FluentTheme.of(
                                  context,
                                ).typography.bodyLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Button(
                                onPressed: () => provider.loadSchedules(),
                                child: const Text('Tentar Novamente'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  if (provider.schedules.isEmpty) {
                    return AppCard(
                      child: EmptyState(
                        icon: FluentIcons.calendar,
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
                        onDuplicate: () =>
                            _duplicateSchedule(context, schedule),
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
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao salvar agendamento',
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text('Tem certeza que deseja excluir este agendamento?'),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          Button(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      final provider = context.read<SchedulerProvider>();
      final success = await provider.deleteSchedule(id);

      if (success && context.mounted) {
        MessageModal.showSuccess(
          context,
          message: 'Agendamento excluído com sucesso!',
        );
      } else if (context.mounted) {
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao excluir agendamento',
        );
      }
    }
  }

  Future<void> _runNow(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Executar Backup'),
        content: const Text('Deseja executar este backup agora?'),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          Button(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.play),
                SizedBox(width: 8),
                Text('Executar'),
              ],
            ),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      final schedulerProvider = context.read<SchedulerProvider>();

      BackupProgressDialog.show(context);

      final success = await schedulerProvider.executeNow(id);

      await Future.delayed(const Duration(seconds: 1));

      if (context.mounted) {
        Navigator.of(context).pop();

        if (success) {
          MessageModal.showSuccess(
            context,
            message: 'Backup executado com sucesso!',
          );
        } else {
          MessageModal.showError(
            context,
            title: 'Erro ao Executar Backup',
            message: schedulerProvider.error ?? 'Erro ao executar backup',
          );
        }
      }
    }
  }

  Future<void> _duplicateSchedule(
    BuildContext context,
    Schedule schedule,
  ) async {
    final provider = context.read<SchedulerProvider>();
    final success = await provider.duplicateSchedule(schedule);

    if (!context.mounted) return;

    if (success) {
      MessageModal.showSuccess(
        context,
        message: 'Agendamento duplicado com sucesso!',
      );
    } else {
      MessageModal.showError(
        context,
        message: provider.error ?? 'Erro ao duplicar agendamento',
      );
    }
  }
}
