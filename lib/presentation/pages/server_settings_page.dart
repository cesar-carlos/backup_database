import 'package:backup_database/application/providers/server_credential_provider.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/server_credential.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/server/server.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('Configurações do Servidor')),
      content: Column(
        children: [
          Expanded(
            child: TabView(
              currentIndex: _selectedTabIndex,
              onChanged: (index) {
                setState(() => _selectedTabIndex = index);
              },
              tabs: [
                Tab(
                  icon: const Icon(FluentIcons.lock),
                  text: const Text('Credenciais de Acesso'),
                  body: _CredentialsTab(
                    onNewCredential: () => _showCredentialDialog(context, null),
                    onEditCredential: (c) => _showCredentialDialog(context, c),
                    onConfirmDelete: _confirmDeleteCredential,
                  ),
                ),
                Tab(
                  icon: const Icon(FluentIcons.people),
                  text: const Text('Clientes Conectados'),
                  body: const Padding(
                    padding: EdgeInsets.all(24),
                    child: ConnectedClientsList(),
                  ),
                ),
                Tab(
                  icon: const Icon(FluentIcons.history),
                  text: const Text('Log de Conexões'),
                  body: const Padding(
                    padding: EdgeInsets.all(24),
                    child: ConnectionLogsList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCredentialDialog(
    BuildContext context,
    ServerCredential? credential,
  ) async {
    final formResult = await ServerCredentialDialog.show(
      context,
      credential: credential,
    );

    if (formResult == null || !context.mounted) return;

    final provider = context.read<ServerCredentialProvider>();

    if (credential == null) {
      final success = await provider.createCredential(
        serverId: formResult.serverId,
        name: formResult.name,
        plainPassword: formResult.plainPassword ?? '',
        isActive: formResult.isActive,
        description: formResult.description,
      );
      if (context.mounted) {
        if (success) {
          MessageModal.showSuccess(
            context,
            message: 'Credencial criada com sucesso.',
          );
        } else {
          MessageModal.showError(
            context,
            message: provider.error ?? 'Erro ao criar credencial.',
          );
        }
      }
    } else {
      final success = await provider.updateCredential(
        credential,
        plainPassword: formResult.plainPassword,
        name: formResult.name,
        isActive: formResult.isActive,
        description: formResult.description,
      );
      if (context.mounted) {
        if (success) {
          MessageModal.showSuccess(
            context,
            message: 'Credencial atualizada com sucesso.',
          );
        } else {
          MessageModal.showError(
            context,
            message: provider.error ?? 'Erro ao atualizar credencial.',
          );
        }
      }
    }
  }

  Future<void> _confirmDeleteCredential(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text(
          'Tem certeza que deseja excluir esta credencial? '
          'Clientes que usam este Server ID não poderão mais conectar.',
        ),
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

    if (confirmed != true || !context.mounted) return;

    final provider = context.read<ServerCredentialProvider>();
    final success = await provider.deleteCredential(id);

    if (context.mounted) {
      if (success) {
        MessageModal.showSuccess(
          context,
          message: 'Credencial excluída com sucesso.',
        );
      } else {
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao excluir credencial.',
        );
      }
    }
  }
}

class _CredentialsTab extends StatelessWidget {
  const _CredentialsTab({
    required this.onNewCredential,
    required this.onEditCredential,
    required this.onConfirmDelete,
  });
  final VoidCallback onNewCredential;
  final ValueChanged<ServerCredential> onEditCredential;
  final void Function(BuildContext context, String id) onConfirmDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommandBar(
            mainAxisAlignment: MainAxisAlignment.end,
            primaryItems: [
              CommandBarButton(
                icon: const Icon(FluentIcons.refresh),
                onPressed: () {
                  context.read<ServerCredentialProvider>().loadCredentials();
                },
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.add),
                label: const Text('Nova Credencial'),
                onPressed: onNewCredential,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Consumer<ServerCredentialProvider>(
              builder: (context, provider, _) {
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
                            style: FluentTheme.of(context).typography.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Button(
                            onPressed: () => provider.loadCredentials(),
                            child: const Text('Tentar Novamente'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (provider.credentials.isEmpty) {
                  return AppCard(
                    child: EmptyState(
                      icon: FluentIcons.lock,
                      message: 'Nenhuma credencial configurada',
                      actionLabel: 'Nova Credencial',
                      onAction: onNewCredential,
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: provider.credentials.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final credential = provider.credentials[index];
                    return ServerCredentialListItem(
                      credential: credential,
                      onEdit: () => onEditCredential(credential),
                      onDelete: () => onConfirmDelete(context, credential.id),
                      onToggleActive: (active) {
                        provider.updateCredential(
                          credential,
                          isActive: active,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
