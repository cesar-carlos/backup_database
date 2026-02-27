import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/sybase_tools_status.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SybaseToolsStatusCard extends StatelessWidget {
  const SybaseToolsStatusCard({
    required this.status,
    this.isLoading = false,
    this.onRefresh,
    super.key,
  });

  final SybaseToolsStatus? status;
  final bool isLoading;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Ferramentas Sybase',
                style: FluentTheme.of(context).typography.subtitle,
              ),
              const Spacer(),
              if (onRefresh != null)
                Tooltip(
                  message: 'Atualizar',
                  child: IconButton(
                    icon: const Icon(FluentIcons.refresh),
                    onPressed: isLoading ? null : onRefresh,
                  ),
                ),
            ],
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: ProgressRing(),
            )
          else if (status == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Não foi possível verificar as ferramentas.',
                style: FluentTheme.of(context).typography.body,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _ToolStatusChip(
                    label: 'dbisql',
                    status: status!.dbisql,
                    required: true,
                  ),
                  _ToolStatusChip(
                    label: 'dbbackup',
                    status: status!.dbbackup,
                    required: true,
                  ),
                  _ToolStatusChip(
                    label: 'dbvalid',
                    status: status!.dbvalid,
                    required: false,
                  ),
                  _ToolStatusChip(
                    label: 'dbverify',
                    status: status!.dbverify,
                    required: false,
                    tooltip: 'Fallback quando dbvalid falha',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolStatusChip extends StatelessWidget {
  const _ToolStatusChip({
    required this.label,
    required this.status,
    required this.required,
    this.tooltip,
  });

  final String label;
  final SybaseToolStatus status;
  final bool required;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (status) {
      SybaseToolStatus.ok => (
        FluentIcons.check_mark,
        AppColors.success,
        'OK',
      ),
      SybaseToolStatus.warning => (
        FluentIcons.warning,
        AppColors.warning,
        'Recomendado',
      ),
      SybaseToolStatus.missing => (
        FluentIcons.cancel,
        AppColors.error,
        required ? 'Faltando' : 'Opcional',
      ),
    };

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: FluentTheme.of(context).typography.body,
          ),
          Text(
            text,
            style: FluentTheme.of(context).typography.bodyStrong?.copyWith(
              color: color,
            ),
          ),
        ],
      ),
    );

    final effectiveTooltip = tooltip;
    if (effectiveTooltip != null) {
      return Tooltip(
        message: effectiveTooltip,
        child: chip,
      );
    }
    return chip;
  }
}
