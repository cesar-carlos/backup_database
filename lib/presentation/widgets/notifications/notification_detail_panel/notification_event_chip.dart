import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — success/error/warning chip for a recipient event.
class NotificationEventChip extends StatelessWidget {
  const NotificationEventChip({
    required this.label,
    required this.enabled,
    required this.tone,
    super.key,
    this.onTap,
  });

  final String label;
  final bool enabled;
  final AppStatusChipTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AppStatusChip(
        label: label,
        tone: enabled ? tone : AppStatusChipTone.neutral,
      ),
    );
  }
}
