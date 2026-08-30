import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — toggle to attach execution logs to outgoing e-mail.
class NotificationAttachLogSection extends StatelessWidget {
  const NotificationAttachLogSection({
    required this.attachLog,
    required this.onAttachLogChanged,
    super.key,
  });

  final bool attachLog;
  final ValueChanged<bool> onAttachLogChanged;

  @override
  Widget build(BuildContext context) {
    final captionStyle = FluentTheme.of(context).typography.caption;
    final outline = context.colors.outline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: outline.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: outline.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appLocaleString(
                    context,
                    'Incluir detalhamento/logs no e-mail',
                    'Include details/logs in e-mail',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  appLocaleString(
                    context,
                    'Útil para suporte e investigação de falhas em campo.',
                    'Useful for support and field failure investigation.',
                  ),
                  style: captionStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ToggleSwitch(
            checked: attachLog,
            onChanged: onAttachLogChanged,
          ),
        ],
      ),
    );
  }
}
