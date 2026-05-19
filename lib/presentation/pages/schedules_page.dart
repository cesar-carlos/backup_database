import 'dart:async';

import 'package:backup_database/application/providers/scheduler_provider.dart';
import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/constants/integrity_ui_strings.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/utils/integrity_error_modal_helper.dart';
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
      unawaited(context.read<SchedulerProvider>().loadSchedules());
    });
  }

  @override
  Widget build(BuildContext context) {
    final features = getIt<FeatureAvailabilityService>();
    final schedulerOk = features.isTaskSchedulerEnabled;

    return AppPageScaffold(
      title: 'Agendamentos',
      actions: [
        AppPageAction(
          label: 'Atualizar',
          icon: FluentIcons.refresh,
          onPressed: () {
            unawaited(context.read<SchedulerProvider>().loadSchedules());
          },
        ),
        AppPageAction(
          label: 'Novo Agendamento',
          icon: FluentIcons.add,
          isPrimary: true,
          onPressed: schedulerOk
              ? () => _showScheduleDialog(context, null)
              : null,
        ),
      ],
      headerBottom: !schedulerOk
          ? InfoBar(
              title: const Text('Agendamentos'),
              content: Text(
                localizeCompatibilityReason(
                  context,
                  reason: features.taskSchedulerDisabledReason,
                  fallbackPt:
                      'Task Scheduler não está disponível nesta versão do Windows.',
                  fallbackEn:
                      'Task Scheduler is not available on this Windows version.',
                ),
              ),
              severity: InfoBarSeverity.warning,
              isLong: true,
            )
          : null,
      body: Consumer<SchedulerProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const SkeletonGrid(rowCount: 8);
          }

          if (provider.error != null) {
            return SingleChildScrollView(
              child: AppPageState.error(
                title: 'Falha ao carregar agendamentos',
                message: provider.error,
                actionLabel: 'Tentar novamente',
                onAction: () => provider.loadSchedules(),
              ),
            );
          }

          if (provider.schedules.isEmpty) {
            return SingleChildScrollView(
              child: AppPageState.empty(
                title: 'Nenhum agendamento configurado',
                message:
                    'Automatize backups, verificacoes e scripts com um fluxo unico.',
                actionLabel: schedulerOk ? 'Criar Agendamento' : null,
                onAction: schedulerOk
                    ? () => _showScheduleDialog(context, null)
                    : null,
              ),
            );
          }

          return ScheduleGrid(
            schedules: provider.schedules,
            scheduleActionsEnabled: schedulerOk,
            onEdit: (schedule) => _showScheduleDialog(context, schedule),
            onDuplicate: (schedule) => _duplicateSchedule(context, schedule),
            onDelete: (id) => _confirmDelete(context, id),
            onRunNow: (id) => _runNow(context, id),
            onToggleEnabled: (schedule, enabled) =>
                provider.toggleSchedule(schedule.id, enabled),
          );
        },
      ),
    );
  }

  Future<void> _showScheduleDialog(
    BuildContext context,
    Schedule? schedule,
  ) async {
    if (!getIt<FeatureAvailabilityService>().isTaskSchedulerEnabled) {
      return;
    }
    final result = await ScheduleDialog.show(context, schedule: schedule);

    if (result != null && context.mounted) {
      final provider = context.read<SchedulerProvider>();
      final success = schedule == null
          ? await provider.createSchedule(result)
          : await provider.updateSchedule(result);

      if (success && context.mounted) {
        unawaited(
          FluentInfoBarFeedback.showSuccess(
            context,
            message: schedule == null
                ? 'Agendamento criado com sucesso!'
                : 'Agendamento atualizado com sucesso!',
          ),
        );
      } else if (context.mounted) {
        unawaited(
          MessageModal.showError(
            context,
            message: provider.error ?? 'Erro ao salvar agendamento',
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    if (!getIt<FeatureAvailabilityService>().isTaskSchedulerEnabled) {
      return;
    }
    final confirmed = await MessageModal.showConfirm(
      context,
      title: 'Confirmar Exclusão',
      message: 'Tem certeza que deseja excluir este agendamento?',
      confirmLabel: 'Excluir',
      confirmIcon: FluentIcons.delete,
    );

    if (confirmed && context.mounted) {
      final provider = context.read<SchedulerProvider>();
      final success = await provider.deleteSchedule(id);

      if (success && context.mounted) {
        unawaited(
          FluentInfoBarFeedback.showSuccess(
            context,
            message: 'Agendamento excluído com sucesso!',
          ),
        );
      } else if (context.mounted) {
        unawaited(
          MessageModal.showError(
            context,
            message: provider.error ?? 'Erro ao excluir agendamento',
          ),
        );
      }
    }
  }

  Future<void> _runNow(BuildContext context, String id) async {
    if (!getIt<FeatureAvailabilityService>().isTaskSchedulerEnabled) {
      return;
    }
    final confirmed = await MessageModal.showConfirm(
      context,
      title: 'Executar Backup',
      message: 'Deseja executar este backup agora?',
      confirmLabel: 'Executar',
      confirmIcon: FluentIcons.play,
    );

    if (confirmed && context.mounted) {
      final schedulerProvider = context.read<SchedulerProvider>();
      final success = await schedulerProvider.executeNow(id);

      if (!success && context.mounted) {
        final code = schedulerProvider.lastErrorCode;
        final message = schedulerProvider.error ?? 'Erro ao executar backup';
        IntegrityErrorModalHelper.showExecutionErrorModal(
          context: context,
          failureCode: code,
          message: message,
          defaultErrorTitleBuilder: IntegrityUiStrings.executeBackupErrorTitle,
        );
      }
    }
  }

  Future<void> _duplicateSchedule(
    BuildContext context,
    Schedule schedule,
  ) async {
    if (!getIt<FeatureAvailabilityService>().isTaskSchedulerEnabled) {
      return;
    }
    final confirmed = await MessageModal.showConfirm(
      context,
      title: 'Duplicar Agendamento',
      message: 'Deseja duplicar o agendamento "${schedule.name}"?',
      confirmLabel: 'Duplicar',
      confirmIcon: FluentIcons.copy,
    );

    if (!confirmed || !context.mounted) {
      return;
    }

    final provider = context.read<SchedulerProvider>();
    final success = await provider.duplicateSchedule(schedule);

    if (!context.mounted) return;

    if (success) {
      unawaited(
        FluentInfoBarFeedback.showSuccess(
          context,
          message: 'Agendamento duplicado com sucesso!',
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao duplicar agendamento',
        ),
      );
    }
  }
}
