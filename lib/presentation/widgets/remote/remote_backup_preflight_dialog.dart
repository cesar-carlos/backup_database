import 'package:backup_database/application/dtos/remote/remote_preflight_view.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

Future<bool?> showRemoteBackupPreflightDialog({
  required BuildContext context,
  required RemotePreflightView preflight,
}) {
  final isBlocked = preflight.isBlocked;
  return showDialog<bool?>(
    context: context,
    builder: (dialogContext) => RemoteBackupPreflightDialog(
      preflight: preflight,
      isBlocked: isBlocked,
    ),
  );
}

class RemoteBackupPreflightDialog extends StatelessWidget {
  const RemoteBackupPreflightDialog({
    required this.preflight,
    required this.isBlocked,
    super.key,
  });

  final RemotePreflightView preflight;
  final bool isBlocked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final failedChecks = preflight.checks.where((c) => !c.passed).toList()
      ..sort(_compareChecksBySeverity);

    return AppDialogShell(
      title: Text(
        isBlocked
            ? appLocaleString(
                context,
                'Pré-verificação bloqueada',
                'Preflight blocked',
              )
            : appLocaleString(
                context,
                'Avisos da pré-verificação',
                'Preflight warnings',
              ),
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isBlocked
                  ? appLocaleString(
                      context,
                      'Corrija os itens abaixo antes de executar o backup no servidor.',
                      'Fix the items below before running backup on the server.',
                    )
                  : appLocaleString(
                      context,
                      'O servidor reportou condições que podem afetar o backup. '
                          'Revise antes de continuar.',
                      'The server reported conditions that may affect backup. '
                          'Review before continuing.',
                    ),
              style: FluentTheme.of(context).typography.body,
            ),
            const SizedBox(height: AppSpacing.md),
            ...failedChecks.map(
              (check) => _PreflightCheckRow(
                check: check,
                colors: colors,
              ),
            ),
          ],
        ),
      ),
      actions: isBlocked
          ? [
              AppButton.primary(
                label: appLocaleString(context, 'Fechar', 'Close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]
          : [
              AppButton(
                label: appLocaleString(context, 'Cancelar', 'Cancel'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              AppButton.primary(
                label: appLocaleString(
                  context,
                  'Continuar mesmo assim',
                  'Continue anyway',
                ),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
    );
  }
}

int _compareChecksBySeverity(
  RemotePreflightCheckView a,
  RemotePreflightCheckView b,
) {
  int rank(RemotePreflightSeverity s) => switch (s) {
    RemotePreflightSeverity.blocking => 0,
    RemotePreflightSeverity.warning => 1,
    RemotePreflightSeverity.info => 2,
  };
  return rank(a.severity).compareTo(rank(b.severity));
}

class _PreflightCheckRow extends StatelessWidget {
  const _PreflightCheckRow({
    required this.check,
    required this.colors,
  });

  final RemotePreflightCheckView check;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(colors);
    final statusLabel = _statusLabel(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_statusIcon(), color: statusColor, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      check.name,
                      style: FluentTheme.of(context).typography.bodyStrong,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      statusLabel,
                      style: FluentTheme.of(
                        context,
                      ).typography.caption?.copyWith(color: statusColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            check.message,
            style: FluentTheme.of(context).typography.body,
          ),
        ],
      ),
    );
  }

  Color _statusColor(AppSemanticColors colors) {
    if (check.passed) {
      return colors.success;
    }
    return switch (check.severity) {
      RemotePreflightSeverity.blocking => colors.danger,
      RemotePreflightSeverity.warning => colors.warning,
      RemotePreflightSeverity.info => colors.info,
    };
  }

  IconData _statusIcon() {
    if (check.passed) {
      return FluentIcons.accept;
    }
    return switch (check.severity) {
      RemotePreflightSeverity.blocking => FluentIcons.cancel,
      RemotePreflightSeverity.warning => FluentIcons.warning,
      RemotePreflightSeverity.info => FluentIcons.info,
    };
  }

  String _statusLabel(BuildContext context) {
    if (check.passed) {
      return appLocaleString(context, 'OK', 'OK');
    }
    return switch (check.severity) {
      RemotePreflightSeverity.blocking => appLocaleString(
        context,
        'Bloqueio',
        'Blocking',
      ),
      RemotePreflightSeverity.warning => appLocaleString(
        context,
        'Aviso',
        'Warning',
      ),
      RemotePreflightSeverity.info => appLocaleString(
        context,
        'Informação',
        'Info',
      ),
    };
  }
}
