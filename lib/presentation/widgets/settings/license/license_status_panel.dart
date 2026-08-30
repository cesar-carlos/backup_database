import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/settings/license/license_status_banner.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

/// **Molecule** — license / trial / revoked status surface.
class LicenseStatusPanel extends StatelessWidget {
  const LicenseStatusPanel({required this.licenseProvider, super.key});

  final LicenseProvider licenseProvider;

  @override
  Widget build(BuildContext context) {
    if (!licenseProvider.isLicenseLoaded) {
      return _LicenseStatusTile(
        leading: const ProgressRing(),
        title: appLocaleString(context, 'Carregando…', 'Loading…'),
        subtitle: appLocaleString(
          context,
          'Consultando licença e período de avaliação',
          'Checking license and evaluation period',
        ),
      );
    }

    final stored = licenseProvider.storedLicense;
    final effective = licenseProvider.effectiveLicense;

    if (licenseProvider.isDeviceRevoked) {
      return _LicenseStatusTile(
        leading: Icon(FluentIcons.blocked, color: context.colors.danger),
        title: appLocaleString(context, 'Licença revogada', 'License revoked'),
        subtitle: appLocaleString(
          context,
          'Este dispositivo está na lista de revogação. A avaliação '
              'não se aplica.',
          'This device is on the revocation list. Evaluation does not apply.',
        ),
      );
    }

    if (stored != null && stored.isValid && !(effective?.isTrial ?? false)) {
      return _LicenseStatusTile(
        leading: Icon(FluentIcons.accept, color: context.colors.success),
        title: appLocaleString(context, 'Licença válida', 'Valid license'),
        subtitle: stored.expiresAt != null
            ? appLocaleString(
                context,
                'Válida até: ${DateFormat('dd/MM/yyyy HH:mm').format(stored.expiresAt!)}',
                'Valid until: ${DateFormat('dd/MM/yyyy HH:mm').format(stored.expiresAt!)}',
              )
            : appLocaleString(
                context,
                'Licença permanente',
                'Permanent license',
              ),
      );
    }

    if (licenseProvider.isTrialActive) {
      final endsAt = effective?.expiresAt;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LicenseStatusTile(
            leading: Icon(FluentIcons.calendar, color: context.colors.info),
            title: appLocaleString(
              context,
              'Período de avaliação',
              'Evaluation period',
            ),
            subtitle: endsAt != null
                ? appLocaleString(
                    context,
                    'Todas as features liberadas até 01/10/2027 '
                        '(${DateFormat('dd/MM/yyyy').format(endsAt)})',
                    'All features unlocked until 01 Oct 2027 '
                        '(${DateFormat('dd/MM/yyyy').format(endsAt)})',
                  )
                : appLocaleString(
                    context,
                    'Todas as features liberadas até 01/10/2027',
                    'All features unlocked until 01 Oct 2027',
                  ),
          ),
          if (LicenseStatusBanner.shouldShow(licenseProvider)) ...[
            AppSpacing.gapSm,
            LicenseStatusBanner(stored: stored!),
          ],
        ],
      );
    }

    if (licenseProvider.isTrialEndedWithoutPremium) {
      return _LicenseStatusTile(
        leading: Icon(FluentIcons.warning, color: context.colors.warning),
        title: appLocaleString(
          context,
          'Avaliação encerrada',
          'Evaluation ended',
        ),
        subtitle: appLocaleString(
          context,
          'Backup full + local/FTP continua. Recursos premium ficam '
              'inativos até ativar uma licença.',
          'Full backup + local/FTP still runs. Premium features stay '
              'inactive until a license is activated.',
        ),
      );
    }

    if (stored != null && stored.isExpired) {
      final expiresAt = stored.expiresAt;
      return _LicenseStatusTile(
        leading: Icon(FluentIcons.warning, color: context.colors.warning),
        title: appLocaleString(context, 'Licença expirada', 'Expired license'),
        subtitle: expiresAt != null
            ? appLocaleString(
                context,
                'Expirou em: ${DateFormat('dd/MM/yyyy HH:mm').format(expiresAt)}',
                'Expired on: ${DateFormat('dd/MM/yyyy HH:mm').format(expiresAt)}',
              )
            : appLocaleString(
                context,
                'Sem data de expiração registrada',
                'No expiration date recorded',
              ),
      );
    }

    if (stored != null && stored.isNotYetValid) {
      final notBefore = stored.notBefore!;
      return _LicenseStatusTile(
        leading: Icon(FluentIcons.warning, color: context.colors.warning),
        title: appLocaleString(
          context,
          'Licença ainda não em vigor',
          'License not yet active',
        ),
        subtitle: appLocaleString(
          context,
          'Válida a partir de: ${DateFormat('dd/MM/yyyy HH:mm').format(notBefore)}',
          'Valid from: ${DateFormat('dd/MM/yyyy HH:mm').format(notBefore)}',
        ),
      );
    }

    return _LicenseStatusTile(
      leading: Icon(FluentIcons.cancel, color: context.colors.danger),
      title: appLocaleString(context, 'Sem licença', 'No license'),
      subtitle: appLocaleString(
        context,
        'Nenhuma licença válida encontrada',
        'No valid license found',
      ),
    );
  }
}

class _LicenseStatusTile extends StatelessWidget {
  const _LicenseStatusTile({
    required this.leading,
    required this.title,
    required this.subtitle,
  });

  final Widget leading;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}
