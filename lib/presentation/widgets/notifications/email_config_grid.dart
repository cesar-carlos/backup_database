import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class EmailConfigGrid extends StatelessWidget {
  const EmailConfigGrid({
    required this.configs,
    required this.selectedConfigId,
    required this.canManage,
    required this.isLoading,
    required this.isTesting,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onSelect,
    required this.onTest,
    required this.onToggleEnabled,
    super.key,
  });

  final List<EmailConfig> configs;
  final String? selectedConfigId;
  final bool canManage;
  final bool isLoading;
  final bool isTesting;
  final VoidCallback onCreate;
  final ValueChanged<EmailConfig> onEdit;
  final ValueChanged<EmailConfig> onDelete;
  final ValueChanged<EmailConfig> onSelect;
  final VoidCallback onTest;
  final void Function(EmailConfig config, bool enabled) onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const AppCard(
        child: SizedBox(
          height: 120,
          child: Center(child: ProgressRing()),
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Configuracoes SMTP',
                style: FluentTheme.of(context).typography.subtitle?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              ActionButton(
                label: isTesting ? 'Testando...' : 'Testar conexao',
                icon: FluentIcons.network_tower,
                isLoading: isTesting,
                onPressed: canManage && selectedConfigId != null
                    ? onTest
                    : null,
              ),
              const SizedBox(width: 12),
              Button(
                onPressed: canManage ? onCreate : null,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.add),
                    SizedBox(width: 8),
                    Text('Nova configuracao'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (configs.isEmpty)
            EmptyState(
              icon: FluentIcons.mail,
              message: 'Nenhuma configuracao de e-mail cadastrada',
              actionLabel: 'Nova configuracao',
              onAction: canManage ? onCreate : null,
            )
          else
            AppDataGrid<EmailConfig>(
              minWidth: 1100,
              columns: [
                AppDataGridColumn<EmailConfig>(
                  label: 'Selecionar',
                  width: const FixedColumnWidth(90),
                  cellAlignment: Alignment.center,
                  cellBuilder: (context, row) => RadioButton(
                    checked: row.id == selectedConfigId,
                    onChanged: (_) => onSelect(row),
                    content: const SizedBox.shrink(),
                  ),
                ),
                AppDataGridColumn<EmailConfig>(
                  label: 'Nome',
                  width: const FlexColumnWidth(1.5),
                  cellBuilder: (context, row) => Text(row.configName),
                ),
                AppDataGridColumn<EmailConfig>(
                  label: 'Servidor SMTP',
                  width: const FlexColumnWidth(1.8),
                  cellBuilder: (context, row) => Text(row.smtpServer),
                ),
                AppDataGridColumn<EmailConfig>(
                  label: 'Porta',
                  width: const FlexColumnWidth(0.7),
                  cellBuilder: (context, row) => Text('${row.smtpPort}'),
                ),
                AppDataGridColumn<EmailConfig>(
                  label: 'Usuario',
                  width: const FlexColumnWidth(1.6),
                  cellBuilder: (context, row) => Text(row.username),
                ),
                AppDataGridColumn<EmailConfig>(
                  label: 'Status',
                  width: const FlexColumnWidth(1.2),
                  cellBuilder: (context, row) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ToggleSwitch(
                        checked: row.enabled,
                        onChanged: canManage
                            ? (value) => onToggleEnabled(row, value)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(row.enabled ? 'Ativo' : 'Inativo'),
                    ],
                  ),
                ),
              ],
              actions: [
                AppDataGridAction<EmailConfig>(
                  icon: FluentIcons.edit,
                  tooltip: 'Editar',
                  onPressed: onEdit,
                  isEnabled: (_) => canManage,
                ),
                AppDataGridAction<EmailConfig>(
                  icon: FluentIcons.delete,
                  tooltip: 'Excluir',
                  onPressed: onDelete,
                  isEnabled: (_) => canManage,
                ),
              ],
              rows: configs,
            ),
        ],
      ),
    );
  }
}
