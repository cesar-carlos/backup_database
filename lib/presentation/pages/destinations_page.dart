import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../application/providers/destination_provider.dart';
import '../../domain/entities/backup_destination.dart';
import '../widgets/common/common.dart';
import '../widgets/destinations/destinations.dart';

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
        padding: const EdgeInsets.all(24),
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
                            Icon(
                              FluentIcons.error,
                              size: 64,
                              color: AppColors.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              provider.error!,
                              style: FluentTheme.of(context).typography.bodyLarge,
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

                  return ListView.separated(
                    itemCount: provider.destinations.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final destination = provider.destinations[index];
                      return DestinationListItem(
                        destination: destination,
                        onEdit: () =>
                            _showDestinationDialog(context, destination),
                        onDelete: () => _confirmDelete(context, destination.id),
                        onToggleEnabled: (enabled) =>
                            provider.toggleEnabled(destination.id, enabled),
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
        MessageModal.showSuccess(
          context,
          message: destination == null
              ? 'Destino criado com sucesso!'
              : 'Destino atualizado com sucesso!',
        );
      } else if (context.mounted) {
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao salvar destino',
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text('Tem certeza que deseja excluir este destino?'),
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

    if (confirmed == true && context.mounted) {
      final provider = context.read<DestinationProvider>();
      final success = await provider.deleteDestination(id);

      if (success && context.mounted) {
        MessageModal.showSuccess(
          context,
          message: 'Destino excluído com sucesso!',
        );
      } else if (context.mounted) {
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao excluir destino',
        );
      }
    }
  }
}
