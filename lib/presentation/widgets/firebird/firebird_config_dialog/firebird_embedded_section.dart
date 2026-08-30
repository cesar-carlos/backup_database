import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — embedded vs client/server toggle.
class FirebirdEmbeddedSection extends StatelessWidget {
  const FirebirdEmbeddedSection({
    required this.useEmbedded,
    required this.onChanged,
    super.key,
  });

  final bool useEmbedded;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InfoLabel(
      label: appLocaleString(
        context,
        'Modo embedded',
        'Embedded mode',
      ),
      child: ToggleSwitch(
        checked: useEmbedded,
        onChanged: onChanged,
      ),
    );
  }
}
