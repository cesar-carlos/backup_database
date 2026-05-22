import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_section_title.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — optional Firebird `nbackup -B` level override in
/// ScheduleDialog (Settings tab, Firebird schedules).
class ScheduleDialogFirebirdNbackupLevelSection extends StatelessWidget {
  const ScheduleDialogFirebirdNbackupLevelSection({
    required this.levelController,
    super.key,
  });

  final TextEditingController levelController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSpacing.gapMd,
        const ScheduleDialogSectionTitle('nbackup (opcional)'),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        AppTextField(
          controller: levelController,
          label: 'Nível físico nbackup (-B)',
          hint: 'Vazio = automático (Full 0; incremental 1)',
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Opcional: 0 a 9. Full físico só aceita 0; incrementais aceitam 1 a 9. '
          'Em Firebird 2.5/3.0, níveis >1 exigem ficheiros da cadeia na pasta de '
          'backup. Em Firebird 4.0, incrementais podem usar o GUID do motor '
          r'(RDB$BACKUP_HISTORY) em vez da convenção de nomes na pasta.',
          style: FluentTheme.of(context).typography.caption,
        ),
      ],
    );
  }
}
