import 'package:fluent_ui/fluent_ui.dart';

class ScheduleDialogSectionTitle extends StatelessWidget {
  const ScheduleDialogSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: FluentTheme.of(
        context,
      ).typography.subtitle?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}
