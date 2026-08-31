import 'dart:async';

import 'package:backup_database/application/dtos/remote/run_diagnostics_view.dart';
import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

class RemoteRunDiagnosticsDialog extends StatefulWidget {
  const RemoteRunDiagnosticsDialog({
    required this.provider,
    required this.runId,
    this.scheduleName,
    this.includeErrorDetails = true,
    this.maxLogLines = 500,
    super.key,
  });

  final RemoteSchedulesProvider provider;
  final String runId;
  final String? scheduleName;
  final bool includeErrorDetails;
  final int maxLogLines;

  static Future<void> show(
    BuildContext context, {
    required RemoteSchedulesProvider provider,
    required String runId,
    String? scheduleName,
    bool includeErrorDetails = true,
    int maxLogLines = 500,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => RemoteRunDiagnosticsDialog(
        provider: provider,
        runId: runId,
        scheduleName: scheduleName,
        includeErrorDetails: includeErrorDetails,
        maxLogLines: maxLogLines,
      ),
    );
  }

  @override
  State<RemoteRunDiagnosticsDialog> createState() =>
      _RemoteRunDiagnosticsDialogState();
}

class _RemoteRunDiagnosticsDialogState
    extends State<RemoteRunDiagnosticsDialog> {
  bool _isLoading = true;
  RunDiagnosticsView? _diagnostics;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _diagnostics = null;
    });

    final diagnostics = await widget.provider.loadRunDiagnostics(
      widget.runId,
      includeErrorDetails: widget.includeErrorDetails,
      maxLogLines: widget.maxLogLines,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _diagnostics = diagnostics;
    });
  }

  Future<void> _copyAllToClipboard() async {
    final buffer = StringBuffer();
    buffer.writeln('=== Diagnóstico run ${widget.runId} ===');
    if (widget.scheduleName != null) {
      buffer.writeln('Agendamento: ${widget.scheduleName}');
    }
    buffer.writeln();

    final details = _diagnostics?.errorDetails;
    if (details != null && details.found) {
      buffer.writeln('--- Detalhes do erro ---');
      if (details.errorCode != null) {
        buffer.writeln(
          'Código: ${details.errorCode} '
          '(${details.errorCodeMessage ?? ''})',
        );
      }
      if (details.errorMessage != null) {
        buffer.writeln('Mensagem: ${details.errorMessage}');
      }
      if (details.stackTrace != null) {
        buffer.writeln('Stack trace:');
        buffer.writeln(details.stackTrace);
      }
      if (details.context != null && details.context!.isNotEmpty) {
        buffer.writeln('Contexto: ${details.context}');
      }
      buffer.writeln();
    }

    final logs = _diagnostics?.logs;
    if (logs != null) {
      buffer.writeln(
        '--- Logs (${logs.lines.length}'
        '${logs.truncated ? "/${logs.totalLines}" : ""} '
        'linhas) ---',
      );
      logs.lines.forEach(buffer.writeln);
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    unawaited(_showCopiedInfoBar());
  }

  Future<void> _showCopiedInfoBar() async {
    await displayInfoBar(
      context,
      builder: (ctx, close) => InfoBar(
        title: Text(
          appLocaleString(
            context,
            'Diagnóstico copiado para a área de transferência',
            'Diagnostics copied to clipboard',
          ),
        ),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final diagnostics = _diagnostics;
    final hasContent = diagnostics?.hasContent ?? false;
    return AppDialogShell(
      constraints: AppDialogConstraints.of(
        context,
        preferredWidth: 760,
      ),
      scrollable: false,
      title: Text(
        widget.scheduleName != null
            ? appLocaleString(
                context,
                'Diagnóstico — ${widget.scheduleName}',
                'Diagnostics — ${widget.scheduleName}',
              )
            : appLocaleString(
                context,
                'Diagnóstico da execução remota',
                'Remote run diagnostics',
              ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              'runId: ${widget.runId}',
              style: FluentTheme.of(context).typography.caption,
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: _isLoading
                  ? const Center(child: ProgressRing())
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ErrorDetailsSection(
                            details: diagnostics?.errorDetails,
                            error: diagnostics?.errorDetailsError,
                            enabled: widget.includeErrorDetails,
                          ),
                          if (widget.includeErrorDetails)
                            const SizedBox(height: AppSpacing.md),
                          _LogsSection(
                            logs: diagnostics?.logs,
                            error: diagnostics?.logsError,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: appLocaleString(context, 'Recarregar', 'Reload'),
          onPressed: _isLoading ? null : () => unawaited(_load()),
        ),
        AppButton(
          label: appLocaleString(context, 'Copiar tudo', 'Copy all'),
          onPressed: hasContent && !_isLoading
              ? () => unawaited(_copyAllToClipboard())
              : null,
        ),
        AppButton.primary(
          label: appLocaleString(context, 'Fechar', 'Close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _ErrorDetailsSection extends StatelessWidget {
  const _ErrorDetailsSection({
    required this.details,
    required this.error,
    required this.enabled,
  });

  final RunDiagnosticsErrorView? details;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appLocaleString(context, 'Erro da execução', 'Run error'),
          style: FluentTheme.of(context).typography.subtitle,
        ),
        const SizedBox(height: AppSpacing.xs),
        if (error != null)
          _ErrorBanner(message: error!)
        else if (details == null)
          Text(
            appLocaleString(
              context,
              'Sem dados de erro disponíveis.',
              'No error data available.',
            ),
            style: FluentTheme.of(context).typography.body,
          )
        else if (!details!.found)
          Text(
            appLocaleString(
              context,
              'O servidor não tem detalhes registrados para este runId.',
              'The server has no error details for this runId.',
            ),
            style: FluentTheme.of(context).typography.body,
          )
        else ...[
          if (details!.errorCode != null)
            SelectableText.rich(
              TextSpan(
                style: FluentTheme.of(context).typography.body,
                children: [
                  TextSpan(
                    text: appLocaleString(context, 'Código: ', 'Code: '),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: details!.errorCode),
                  if (details!.errorCodeMessage != null)
                    TextSpan(
                      text: ' — ${details!.errorCodeMessage}',
                      style: TextStyle(color: colors.danger),
                    ),
                ],
              ),
            ),
          if (details!.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.xs),
            SelectableText(
              details!.errorMessage!,
              style: FluentTheme.of(context).typography.body,
            ),
          ],
          if (details!.stackTrace != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              appLocaleString(context, 'Stack trace', 'Stack trace'),
              style: FluentTheme.of(context).typography.bodyStrong,
            ),
            const SizedBox(height: AppSpacing.xs),
            _MonoBlock(text: details!.stackTrace!),
          ],
          if (details!.context != null && details!.context!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              appLocaleString(context, 'Contexto', 'Context'),
              style: FluentTheme.of(context).typography.bodyStrong,
            ),
            const SizedBox(height: AppSpacing.xs),
            _MonoBlock(text: details!.context!.toString()),
          ],
        ],
      ],
    );
  }
}

class _LogsSection extends StatelessWidget {
  const _LogsSection({required this.logs, required this.error});

  final RunDiagnosticsLogsView? logs;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appLocaleString(context, 'Logs do servidor', 'Server logs'),
          style: FluentTheme.of(context).typography.subtitle,
        ),
        const SizedBox(height: AppSpacing.xs),
        if (error != null)
          _ErrorBanner(message: error!)
        else if (logs == null || logs!.isEmpty)
          Text(
            appLocaleString(
              context,
              'Sem entradas de log para este runId.',
              'No log entries for this runId.',
            ),
            style: FluentTheme.of(context).typography.body,
          )
        else ...[
          Text(
            logs!.truncated
                ? appLocaleString(
                    context,
                    'Exibindo ${logs!.lines.length} de '
                        '${logs!.totalLines} linhas (truncado).',
                    'Showing ${logs!.lines.length} of '
                        '${logs!.totalLines} lines (truncated).',
                  )
                : appLocaleString(
                    context,
                    '${logs!.lines.length} linhas.',
                    '${logs!.lines.length} lines.',
                  ),
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: AppSpacing.xs),
          _MonoBlock(text: logs!.lines.join('\n'), maxHeight: 260),
        ],
      ],
    );
  }
}

class _MonoBlock extends StatelessWidget {
  const _MonoBlock({required this.text, this.maxHeight = 200});

  final String text;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: colors.outline),
        ),
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: TextStyle(
              fontFamily: 'Consolas, Courier New, monospace',
              fontSize: 12,
              color: colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCallout(
      message: '${appLocaleString(context, 'Erro: ', 'Error: ')}$message',
      tone: AppCalloutTone.danger,
    );
  }
}
