import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Semantic tones', type: AppStatusChip)
Widget buildAppStatusChipSemanticUseCase(BuildContext context) {
  return const Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      AppStatusChip(label: 'Ready', tone: AppStatusChipTone.success),
      AppStatusChip(label: 'Syncing', tone: AppStatusChipTone.info),
      AppStatusChip(label: 'Paused', tone: AppStatusChipTone.warning),
      AppStatusChip(label: 'Failed', tone: AppStatusChipTone.danger),
    ],
  );
}

@widgetbook.UseCase(name: 'Accent tag', type: AppStatusChip)
Widget buildAppStatusChipAccentUseCase(BuildContext context) {
  return const AppStatusChip(
    label: 'SQL Server',
    color: AppColors.databaseSqlServer,
    icon: FluentIcons.database,
  );
}
