import 'dart:async';

import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/infrastructure/protocol/diagnostics_messages.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:result_dart/result_dart.dart' as rd;

/// **Organism** — modal que apresenta logs e detalhes de erro de uma
/// execução remota (`runId`) já existente. Consome os RPCs
/// `getRunLogs` e `getRunErrorDetails` do `ConnectionManager` (PR de
/// diagnóstico remoto).
///
/// §audit-2026-05-28 wave 3 (P2): essas mensagens já existiam no
/// protocolo desde a wave 1, mas faltava UI. Operador que precisava
/// investigar um backup `failed` no servidor remoto não tinha como
/// — só via SSH/leitura manual de log. Esta dialog é o ponto central.
class RemoteRunDiagnosticsDialog extends StatefulWidget {
  const RemoteRunDiagnosticsDialog({
    required this.connectionManager,
    required this.runId,
    this.scheduleName,
    this.includeErrorDetails = true,
    this.maxLogLines = 500,
    super.key,
  });

  final ConnectionManager connectionManager;
  final String runId;
  final String? scheduleName;
  final bool includeErrorDetails;
  final int maxLogLines;

  static Future<void> show(
    BuildContext context, {
    required ConnectionManager connectionManager,
    required String runId,
    String? scheduleName,
    bool includeErrorDetails = true,
    int maxLogLines = 500,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => RemoteRunDiagnosticsDialog(
        connectionManager: connectionManager,
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
  RunLogsResult? _logs;
  RunErrorDetailsResult? _errorDetails;
  String? _logsError;
  String? _errorDetailsError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _logs = null;
      _errorDetails = null;
      _logsError = null;
      _errorDetailsError = null;
    });

    // Dispara as duas chamadas em paralelo — operador raramente quer
    // ver logs SEM o detalhe do erro, e quase nunca vice-versa.
    final logsFuture = widget.connectionManager.getRunLogs(
      runId: widget.runId,
      maxLines: widget.maxLogLines,
    );
    final detailsFuture = widget.includeErrorDetails
        ? widget.connectionManager.getRunErrorDetails(runId: widget.runId)
        : Future<rd.Result<RunErrorDetailsResult>?>.value();

    final logsResult = await logsFuture;
    final detailsResult = await detailsFuture;

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      logsResult.fold(
        (logs) => _logs = logs,
        (failure) => _logsError = _failureMessage(failure),
      );
      if (detailsResult != null) {
        detailsResult.fold(
          (details) => _errorDetails = details,
          (failure) => _errorDetailsError = _failureMessage(failure),
        );
      }
    });
  }

  String _failureMessage(Object failure) {
    final str = failure.toString();
    return str.isEmpty ? 'Erro desconhecido' : str;
  }

  Future<void> _copyAllToClipboard() async {
    final buffer = StringBuffer();
    buffer.writeln('=== Diagnóstico run ${widget.runId} ===');
    if (widget.scheduleName != null) {
      buffer.writeln('Agendamento: ${widget.scheduleName}');
    }
    buffer.writeln();

    final details = _errorDetails;
    if (details != null && details.found) {
      buffer.writeln('--- Detalhes do erro ---');
      if (details.errorCode != null) {
        buffer.writeln(
          'Código: ${details.errorCode!.code} '
          '(${details.errorCode!.defaultMessage})',
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

    final logs = _logs;
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
    unawaited(
      _showCopiedInfoBar(),
    );
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
    final hasContent = _errorDetails != null || _logs != null;
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
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
                            details: _errorDetails,
                            error: _errorDetailsError,
                            enabled: widget.includeErrorDetails,
                          ),
                          if (widget.includeErrorDetails)
                            const SizedBox(height: AppSpacing.md),
                          _LogsSection(
                            logs: _logs,
                            error: _logsError,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: _isLoading ? null : _load,
          child: Text(
            appLocaleString(context, 'Recarregar', 'Reload'),
          ),
        ),
        Button(
          onPressed: hasContent && !_isLoading ? _copyAllToClipboard : null,
          child: Text(
            appLocaleString(
              context,
              'Copiar tudo',
              'Copy all',
            ),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            appLocaleString(context, 'Fechar', 'Close'),
          ),
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

  final RunErrorDetailsResult? details;
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
                  TextSpan(text: details!.errorCode!.code),
                  TextSpan(
                    text: ' — ${details!.errorCode!.defaultMessage}',
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

  final RunLogsResult? logs;
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
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        // §audit-2026-05-28 wave 3: `AppSemanticColors` ainda não tem
        // variantes "subtle" — usamos opacidade reduzida do `danger`
        // (~12%) como background tonal seguindo o pattern do Fluent.
        color: colors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: SelectableText.rich(
        TextSpan(
          style: FluentTheme.of(context).typography.body,
          children: [
            TextSpan(
              text: appLocaleString(context, 'Erro: ', 'Error: '),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colors.danger,
              ),
            ),
            TextSpan(
              text: message,
              style: TextStyle(color: colors.danger),
            ),
          ],
        ),
      ),
    );
  }
}
