import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

/// **Organism** — debug-only license generator entry (kDebugMode).
class LicenseGeneratorPanel extends StatelessWidget {
  const LicenseGeneratorPanel({
    required this.canGenerateLicenses,
    required this.isAuthenticatedListenable,
    required this.onOpenAuth,
    required this.onOpenGenerator,
    super.key,
  });

  final bool canGenerateLicenses;
  final ValueListenable<bool> isAuthenticatedListenable;
  final VoidCallback onOpenAuth;
  final VoidCallback onOpenGenerator;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(
        context,
        'Gerador de licenças',
        'License generator',
      ),
      trailing: !canGenerateLicenses
          ? Text(
              appLocaleString(
                context,
                'Indisponível neste ambiente',
                'Unavailable in this environment',
              ),
              style: FluentTheme.of(context).typography.body,
            )
          : ValueListenableBuilder<bool>(
              valueListenable: isAuthenticatedListenable,
              builder: (context, isAuthenticated, child) {
                if (!isAuthenticated) {
                  return AppButton(
                    label: appLocaleString(
                      context,
                      'Acessar gerador',
                      'Open generator',
                    ),
                    onPressed: onOpenAuth,
                  );
                }
                return AppButton(
                  label: appLocaleString(
                    context,
                    'Gerar licença',
                    'Generate license',
                  ),
                  onPressed: onOpenGenerator,
                );
              },
            ),
      banner: InfoBar(
        severity: InfoBarSeverity.warning,
        title: Text(
          appLocaleString(
            context,
            'Modo de desenvolvedor',
            'Developer mode',
          ),
        ),
        content: Text(
          appLocaleString(
            context,
            'Este gerador requer chave privada Ed25519 (BACKUP_DATABASE_LICENSE_PRIVATE_KEY). '
                'NUNCA distribua a chave privada para clientes. '
                'Use este gerador apenas em ambiente controlado.',
            'This generator requires Ed25519 private key (BACKUP_DATABASE_LICENSE_PRIVATE_KEY). '
                'NEVER distribute the private key to clients. '
                'Use this generator only in controlled environment.',
          ),
        ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}
