import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:fluent_ui/fluent_ui.dart';

Future<bool?> showRemoteBackupPreflightDialog({
  required BuildContext context,
  required PreflightResult preflight,
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

  final PreflightResult preflight;
  final bool isBlocked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final failedChecks = preflight.checks.where((c) => !c.passed).toList()
      ..sort(_compareChecksBySeverity);

    return ContentDialog(
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
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  appLocaleString(context, 'Fechar', 'Close'),
                ),
              ),
            ]
          : [
              Button(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  appLocaleString(context, 'Cancelar', 'Cancel'),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  appLocaleString(
                    context,
                    'Continuar mesmo assim',
                    'Continue anyway',
                  ),
                ),
              ),
            ],
    );
  }
}

int _compareChecksBySeverity(
  PreflightCheckResult a,
  PreflightCheckResult b,
) {
  int rank(PreflightSeverity s) => switch (s) {
    PreflightSeverity.blocking => 0,
    PreflightSeverity.warning => 1,
    PreflightSeverity.info => 2,
  };
  return rank(a.severity).compareTo(rank(b.severity));
}

class _PreflightCheckRow extends StatelessWidget {
  const _PreflightCheckRow({
    required this.check,
    required this.colors,
  });

  final PreflightCheckResult check;
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
      PreflightSeverity.blocking => colors.danger,
      PreflightSeverity.warning => colors.warning,
      PreflightSeverity.info => colors.info,
    };
  }

  IconData _statusIcon() {
    if (check.passed) {
      return FluentIcons.accept;
    }
    return switch (check.severity) {
      PreflightSeverity.blocking => FluentIcons.cancel,
      PreflightSeverity.warning => FluentIcons.warning,
      PreflightSeverity.info => FluentIcons.info,
    };
  }

  String _statusLabel(BuildContext context) {
    if (check.passed) {
      return appLocaleString(context, 'OK', 'OK');
    }
    return switch (check.severity) {
      PreflightSeverity.blocking => appLocaleString(
        context,
        'Bloqueio',
        'Blocking',
      ),
      PreflightSeverity.warning => appLocaleString(
        context,
        'Aviso',
        'Warning',
      ),
      PreflightSeverity.info => appLocaleString(
        context,
        'Informação',
        'Info',
      ),
    };
  }
}
