import 'dart:async';

import 'package:backup_database/application/providers/remote_database_config_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

String _l(BuildContext context, String pt, String en) =>
    appLocaleString(context, pt, en);

class RemoteDatabaseConfigsPage extends StatefulWidget {
  const RemoteDatabaseConfigsPage({super.key});

  @override
  State<RemoteDatabaseConfigsPage> createState() =>
      _RemoteDatabaseConfigsPageState();
}

class _RemoteDatabaseConfigsPageState extends State<RemoteDatabaseConfigsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfConnected());
  }

  void _loadIfConnected() {
    if (context.read<ServerConnectionProvider>().isConnected) {
      unawaited(context.read<RemoteDatabaseConfigProvider>().loadConfigs());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: _l(context, 'Bancos no servidor', 'Server databases'),
      body: Consumer<ServerConnectionProvider>(
        builder: (context, connectionProvider, _) {
          if (!connectionProvider.isConnected) {
            return AppPageState.empty(
              title: _l(
                context,
                'Conecte-se a um servidor',
                'Connect to a server',
              ),
              message: _l(
                context,
                'Vá em Conectar para adicionar e conectar a um servidor.',
                'Go to Connect to add and connect to a server.',
              ),
              actionLabel: _l(context, 'Ir para Conectar', 'Go to Connect'),
              onAction: () => context.go(RouteNames.serverLogin),
            );
          }
          return Consumer<RemoteDatabaseConfigProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading && provider.entries.isEmpty) {
                return AppPageState.loading(
                  title: _l(context, 'Carregando bancos', 'Loading databases'),
                );
              }
              if (provider.error != null && provider.entries.isEmpty) {
                return AppPageState.error(
                  title: _l(
                    context,
                    'Falha ao carregar bancos',
                    'Failed to load databases',
                  ),
                  message: provider.error,
                  actionLabel: _l(context, 'Tentar novamente', 'Retry'),
                  onAction: () => unawaited(provider.loadConfigs()),
                );
              }
              if (provider.entries.isEmpty) {
                return AppPageState.empty(
                  title: _l(
                    context,
                    'Nenhum banco no servidor',
                    'No databases on server',
                  ),
                  message: _l(
                    context,
                    'O servidor não publicou configurações de banco.',
                    'The server has no database configs.',
                  ),
                  actionLabel: _l(context, 'Atualizar', 'Refresh'),
                  onAction: () => unawaited(provider.loadConfigs()),
                );
              }
              return ListView.separated(
                itemCount: provider.entries.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) =>
                    _RemoteDatabaseConfigTile(entry: provider.entries[index]),
              );
            },
          );
        },
      ),
    );
  }
}

class _RemoteDatabaseConfigTile extends StatelessWidget {
  const _RemoteDatabaseConfigTile({required this.entry});

  final RemoteDatabaseConfigEntry entry;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RemoteDatabaseConfigProvider>();
    final busy =
        provider.isTesting(entry.listKey) || provider.isDeleting(entry.listKey);

    return Card(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  remoteDatabaseTypeLabel(entry.databaseType),
                  style: FluentTheme.of(context).typography.caption?.copyWith(
                    color: context.colors.disabled,
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: _l(context, 'Testar conexão', 'Test connection'),
            child: IconButton(
              icon: const Icon(FluentIcons.plug_connected),
              onPressed: busy ? null : () => unawaited(_onTest(context)),
            ),
          ),
          Tooltip(
            message: _l(context, 'Excluir', 'Delete'),
            child: IconButton(
              icon: Icon(FluentIcons.delete, color: context.colors.danger),
              onPressed: busy ? null : () => unawaited(_onDelete(context)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onTest(BuildContext context) async {
    final message = await context
        .read<RemoteDatabaseConfigProvider>()
        .testConnection(entry);
    if (!context.mounted) return;
    if (message == null) {
      await FluentInfoBarFeedback.showSuccess(
        context,
        message: _l(context, 'Conexão OK', 'Connection OK'),
      );
      return;
    }
    await FluentInfoBarFeedback.showWarning(context, message: message);
  }

  Future<void> _onDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: Text(_l(dialogContext, 'Confirmar exclusão', 'Confirm delete')),
        content: Text(
          _l(
            dialogContext,
            'Excluir "${entry.name}" no servidor?',
            'Delete "${entry.name}" on the server?',
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_l(dialogContext, 'Cancelar', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_l(dialogContext, 'Excluir', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await context.read<RemoteDatabaseConfigProvider>().deleteConfig(
      entry,
    );
    if (!context.mounted || !ok) return;
    await FluentInfoBarFeedback.showSuccess(
      context,
      message: _l(context, 'Banco excluído', 'Database deleted'),
    );
  }
}
