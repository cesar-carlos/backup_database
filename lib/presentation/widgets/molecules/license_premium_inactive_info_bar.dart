import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — aviso permanente quando uma config já usa premium
/// bloqueado (downgrade sem wipe).
class LicensePremiumInactiveInfoBar extends StatelessWidget {
  const LicensePremiumInactiveInfoBar({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoBar(
      severity: InfoBarSeverity.warning,
      isLong: true,
      title: Text(
        appLocaleString(
          context,
          'Recursos premium inativos',
          'Premium features inactive',
        ),
      ),
      content: Text(
        appLocaleString(
          context,
          'Esta configuração permanece salva, mas não executa até '
              'ativar uma licença premium.',
          'This configuration stays saved, but will not run until a '
              'premium license is activated.',
        ),
      ),
    );
  }
}
