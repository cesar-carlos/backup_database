import 'dart:async';

import 'package:backup_database/application/providers/destination_provider.dart';
import 'package:backup_database/application/providers/scheduler_provider.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destinations.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class DestinationsPage extends StatelessWidget {
  const DestinationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Destinos de Backup',
      actions: [
        AppPageAction(
          label: 'Atualizar',
          icon: FluentIcons.refresh,
          onPressed: () {
            unawaited(context.read<DestinationProvider>().loadDestinations());
          },
        ),
        AppPageAction(
          label: 'Novo Destino',
          icon: FluentIcons.add,
          isPrimary: true,
          onPressed: () => _showDestinationDialog(context, null),
        ),
      ],
      body: Consumer<DestinationProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return AppPageState.loading(
              title: 'Carregando destinos',
              message: 'Buscando destinos configurados na aplicacao.',
            );
          }

          if (provider.error != null) {
            return AppPageState.error(
              title: 'Falha ao carregar destinos',
              message: provider.error,
              actionLabel: 'Tentar novamente',
              onAction: () => provider.loadDestinations(),
            );
          }

          if (provider.destinations.isEmpty) {
            return AppPageState.empty(
              title: 'Nenhum destino de backup configurado',
              message:
                  'Organize os destinos usados pelos backups e transferencias.',
              actionLabel: 'Adicionar Destino',
              onAction: () => _showDestinationDialog(context, null),
            );
          }

          return DestinationGrid(
            destinations: provider.destinations,
            onEdit: (destination) =>
                _showDestinationDialog(context, destination),
            onDuplicate: (destination) =>
                _duplicateDestination(context, destination),
            onDelete: (id) => _confirmDelete(context, id),
            onToggleEnabled: (destination, enabled) =>
                provider.toggleEnabled(destination.id, enabled),
          );
        },
      ),
    );
  }

  Future<void> _showDestinationDialog(
    BuildContext context,
    BackupDestination? destination,
  ) async {
    final result = await DestinationDialog.show(
      context,
      destination: destination,
    );

    if (result != null && context.mounted) {
      final provider = context.read<DestinationProvider>();
      final success = destination == null
          ? await provider.createDestination(result)
          : await provider.updateDestination(result);

      if (success && context.mounted) {
        await FluentInfoBarFeedback.showSuccess(
          context,
          message: destination == null
              ? 'Destino criado com sucesso!'
              : 'Destino atualizado com sucesso!',
        );
      } else if (context.mounted) {
        await MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao salvar destino',
        );
      }
    }
  }

  Future<void> _duplicateDestination(
    BuildContext context,
    BackupDestination destination,
  ) async {
    final confirmed = await MessageModal.showConfirm(
      context,
      title: 'Duplicar Destino',
      message: 'Tem certeza que deseja duplicar "${destination.name}"?',
      confirmLabel: 'Duplicar',
      confirmIcon: FluentIcons.copy,
    );

    if (!confirmed || !context.mounted) return;

    final provider = context.read<DestinationProvider>();
    final success = await provider.duplicateDestination(destination);

    if (!context.mounted) return;

    if (success) {
      await FluentInfoBarFeedback.showSuccess(
        context,
        message: 'Destino duplicado com sucesso!',
      );
    } else {
      await MessageModal.showError(
        context,
        message: provider.error ?? 'Erro ao duplicar destino',
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final destinationProvider = context.read<DestinationProvider>();
    final destinationName =
        destinationProvider.getDestinationById(id)?.name ?? 'Destino';

    final linkedSchedules = await context
        .read<SchedulerProvider>()
        .getSchedulesByDestination(id);

    if (!context.mounted) return;

    if (linkedSchedules == null) {
      await MessageModal.showError(
        context,
        message:
            'Não foi possível validar dependências do destino. Tente novamente.',
      );
      return;
    }

    if (linkedSchedules.isNotEmpty) {
      final action = await DestinationDependencyDialog.show(
        context,
        destinationName: destinationName,
        schedules: linkedSchedules,
      );

      if (!context.mounted) return;

      if (action == DestinationDependencyDialogAction.goToSchedules) {
        context.go(RouteNames.schedules);
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text('Tem certeza que deseja excluir este destino?'),
        actions: [
          CancelButton(onPressed: () => Navigator.of(context).pop(false)),
          ActionButton(
            label: 'Excluir',
            icon: FluentIcons.delete,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      final success = await destinationProvider.deleteDestination(id);
      if (!context.mounted) return;

      if (success) {
        await FluentInfoBarFeedback.showSuccess(
          context,
          message: 'Destino excluido com sucesso!',
        );
      } else {
        await MessageModal.showError(
          context,
          message: destinationProvider.error ?? 'Erro ao excluir destino',
        );
      }
    }
  }
}
