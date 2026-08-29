import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — retention, date subfolders, and enabled toggle.
class DestinationDialogBehaviorSection extends StatelessWidget {
  const DestinationDialogBehaviorSection({
    required this.selectedType,
    required this.retentionDaysController,
    required this.createSubfoldersByDate,
    required this.isEnabled,
    required this.labelBuilder,
    required this.onCreateSubfoldersByDateChanged,
    required this.onEnabledChanged,
    super.key,
  });

  final DestinationType selectedType;
  final TextEditingController retentionDaysController;
  final bool createSubfoldersByDate;
  final bool isEnabled;
  final DestinationDialogLabelBuilder labelBuilder;
  final ValueChanged<bool> onCreateSubfoldersByDateChanged;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: labelBuilder(
        'Comportamento e retenção',
        'Behavior and retention',
      ),
      description: labelBuilder(
        'Controle limpeza automática, disponibilidade do destino e preferências adicionais.',
        'Control automatic cleanup, destination availability and additional preferences.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NumericField(
            controller: retentionDaysController,
            label: labelBuilder('Dias de retenção', 'Retention days'),
            hint: labelBuilder(
              'Ex: 7 (mantem backups por 7 dias)',
              'Ex: 7 (keeps backups for 7 days)',
            ),
            prefixIcon: FluentIcons.delete,
            minValue: 1,
          ),
          const SizedBox(height: AppSpacing.sm),
          _RetentionInfo(retentionDaysController: retentionDaysController),
          if (selectedType == DestinationType.local) ...[
            const SizedBox(height: AppSpacing.md),
            LabeledToggle(
              title: labelBuilder(
                'Criar subpastas por data',
                'Create date-based subfolders',
              ),
              value: createSubfoldersByDate,
              onChanged: onCreateSubfoldersByDateChanged,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          LabeledToggle(
            title: labelBuilder('Habilitado', 'Enabled'),
            description: labelBuilder(
              'Destino ativo para uso em agendamentos',
              'Destination active for schedule use',
            ),
            value: isEnabled,
            onChanged: onEnabledChanged,
          ),
        ],
      ),
    );
  }
}

class _RetentionInfo extends StatelessWidget {
  const _RetentionInfo({required this.retentionDaysController});

  final TextEditingController retentionDaysController;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        borderRadius: AppRadius.circularMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FluentIcons.info, size: 20, color: context.colors.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: retentionDaysController,
              builder: (BuildContext context, TextEditingValue value, _) {
                final days = int.tryParse(value.text) ?? 7;
                final cutoffDate = DateTime.now().subtract(
                  Duration(days: days),
                );
                final formatted = _formatDate(cutoffDate);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destinationDialogLabel(
                        context,
                        'Limpeza automática',
                        'Automatic cleanup',
                      ),
                      style: FluentTheme.of(context).typography.caption
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: context.colors.info,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      destinationDialogLabel(
                        context,
                        'Backups anteriores a $formatted serão excluídos automaticamente após cada backup executado.',
                        'Backups older than $formatted will be automatically removed after each backup run.',
                      ),
                      style: FluentTheme.of(context).typography.caption,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}
