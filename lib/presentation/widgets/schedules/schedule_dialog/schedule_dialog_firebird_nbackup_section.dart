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
          'Opcional: 0 a 9. Para niveis >1 e necessario ficheiros da cadeia '
          'na pasta de backup (ver documentacao Firebird nbackup). '
          'Full fisico so aceita 0; incrementais aceitam 1 a 9.',
          style: FluentTheme.of(context).typography.caption,
        ),
      ],
    );
  }
}
