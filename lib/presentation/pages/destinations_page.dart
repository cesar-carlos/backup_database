import 'package:backup_database/application/providers/destination_provider.dart';
import 'package:backup_database/application/providers/scheduler_provider.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/theme/app_colors.dart';
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
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Destinos de Backup'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: () {
                context.read<DestinationProvider>().loadDestinations();
              },
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('Novo Destino'),
              onPressed: () => _showDestinationDialog(context, null),
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Consumer<DestinationProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading) {
                    return const Center(child: ProgressRing());
                  }

                  if (provider.error != null) {
                    return AppCard(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
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
                              onPressed: () => provider.loadDestinations(),
                              child: const Text('Tentar Novamente'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (provider.destinations.isEmpty) {
                    return AppCard(
                      child: EmptyState(
                        icon: FluentIcons.folder,
                        message: 'Nenhum destino de backup configurado',
                        actionLabel: 'Adicionar Destino',
                        onAction: () => _showDestinationDialog(context, null),
                      ),
                    );
                  }

                  return DestinationGrid(
                    destinations: provider.destinations,
                    onEdit: (destination) =>
                        _showDestinationDialog(context, destination),
                    onDelete: (id) => _confirmDelete(context, id),
                    onToggleEnabled: (destination, enabled) =>
                        provider.toggleEnabled(destination.id, enabled),
                  );
                },
              ),
            ),
          ],
        ),
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
        await MessageModal.showSuccess(
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
        await MessageModal.showSuccess(
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
