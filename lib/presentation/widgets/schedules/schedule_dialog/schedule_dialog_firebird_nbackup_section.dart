import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_section_title.dart';
import 'package:fluent_ui/fluent_ui.dart';

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
        const SizedBox(height: 16),
        const ScheduleDialogSectionTitle('nbackup (opcional)'),
        const SizedBox(height: 12),
        AppTextField(
          controller: levelController,
          label: 'Nivel fisico nbackup (-B)',
          hint: 'Vazio = automatico (Full 0; incremental 1)',
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 8),
        Text(
          'Opcional: 0 a 9. Full fisico so aceita 0; incrementais aceitam 1 a 9. '
          'Em Firebird 2.5/3.0, niveis >1 exigem ficheiros da cadeia na pasta de '
          'backup. Em Firebird 4.0, incrementais podem usar o GUID do motor '
          r'(RDB$BACKUP_HISTORY) em vez da convencao de nomes na pasta.',
          style: FluentTheme.of(context).typography.caption,
        ),
      ],
    );
  }
}
