import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class EmailTargetGrid extends StatelessWidget {
  const EmailTargetGrid({
    required this.targets,
    required this.canManage,
    required this.hasSelectedConfig,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
    super.key,
  });

  final List<EmailNotificationTarget> targets;
  final bool canManage;
  final bool hasSelectedConfig;
  final VoidCallback onAdd;
  final ValueChanged<EmailNotificationTarget> onEdit;
  final ValueChanged<EmailNotificationTarget> onDelete;
  final void Function(EmailNotificationTarget target, bool enabled)
  onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Destinatarios da configuracao selecionada',
                style: FluentTheme.of(context).typography.subtitle?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Button(
                onPressed: canManage && hasSelectedConfig ? onAdd : null,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.add),
                    SizedBox(width: 8),
                    Text('Adicionar destinatario'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasSelectedConfig)
            const EmptyState(
              icon: FluentIcons.mail,
              message:
                  'Selecione uma configuracao SMTP para gerenciar destinatarios',
            )
          else if (targets.isEmpty)
            EmptyState(
              icon: FluentIcons.group,
              message: 'Nenhum destinatario cadastrado',
              actionLabel: 'Adicionar destinatario',
              onAction: canManage ? onAdd : null,
            )
          else
            AppDataGrid<EmailNotificationTarget>(
              minWidth: 1000,
              columns: [
                AppDataGridColumn<EmailNotificationTarget>(
                  label: 'E-mail',
                  width: const FlexColumnWidth(2.4),
                  cellBuilder: (context, row) => Text(row.recipientEmail),
                ),
                AppDataGridColumn<EmailNotificationTarget>(
                  label: 'Sucesso',
                  width: const FlexColumnWidth(0.9),
                  cellAlignment: Alignment.center,
                  cellBuilder: (context, row) => _flagIcon(row.notifyOnSuccess),
                ),
                AppDataGridColumn<EmailNotificationTarget>(
                  label: 'Erro',
                  width: const FlexColumnWidth(0.9),
                  cellAlignment: Alignment.center,
                  cellBuilder: (context, row) => _flagIcon(row.notifyOnError),
                ),
                AppDataGridColumn<EmailNotificationTarget>(
                  label: 'Aviso',
                  width: const FlexColumnWidth(0.9),
                  cellAlignment: Alignment.center,
                  cellBuilder: (context, row) => _flagIcon(row.notifyOnWarning),
                ),
                AppDataGridColumn<EmailNotificationTarget>(
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
                AppDataGridAction<EmailNotificationTarget>(
                  icon: FluentIcons.edit,
                  tooltip: 'Editar',
                  onPressed: onEdit,
                  isEnabled: (_) => canManage,
                ),
                AppDataGridAction<EmailNotificationTarget>(
                  icon: FluentIcons.delete,
                  tooltip: 'Excluir',
                  onPressed: onDelete,
                  isEnabled: (_) => canManage,
                ),
              ],
              rows: targets,
            ),
        ],
      ),
    );
  }

  Widget _flagIcon(bool enabled) {
    return Icon(
      enabled ? FluentIcons.checkbox_composite : FluentIcons.checkbox,
      size: 16,
    );
  }
}
