import 'dart:async';

import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/use_cases/backup/get_sybase_backup_health.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

class SybaseBackupHealthCard extends StatefulWidget {
  const SybaseBackupHealthCard({super.key});

  @override
  State<SybaseBackupHealthCard> createState() => _SybaseBackupHealthCardState();
}

class _SybaseBackupHealthCardState extends State<SybaseBackupHealthCard> {
  BackupHistory? _lastFull;
  BackupHistory? _lastLog;
  SybaseChainStatus _chainStatus = SybaseChainStatus.ok;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHealth());
  }

  Future<void> _loadHealth() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final useCase = GetIt.instance<GetSybaseBackupHealth>();
      final result = await useCase();

      result.fold(
        (health) {
          if (mounted) {
            setState(() {
              _lastFull = health.lastFull;
              _lastLog = health.lastLog;
              _chainStatus = health.chainStatus;
              _isLoading = false;
            });
          }
        },
        (failure) {
          if (mounted) {
            setState(() {
              _error = failureUserMessage(failure);
              _isLoading = false;
            });
          }
        },
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Saúde dos Backups Sybase',
                style: FluentTheme.of(context).typography.subtitle,
              ),
              const Spacer(),
              Tooltip(
                message: 'Atualizar',
                child: IconButton(
                  icon: const Icon(FluentIcons.refresh),
                  onPressed: _isLoading ? null : _loadHealth,
                ),
              ),
            ],
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: ProgressRing(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: FluentTheme.of(context).typography.body?.copyWith(
                  color: context.colors.danger,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _HealthChip(
                    label: 'Último Full',
                    value: _lastFull != null
                        ? DateFormat('dd/MM/yyyy HH:mm').format(
                            _lastFull!.finishedAt ?? _lastFull!.startedAt,
                          )
                        : '—',
                    status: _chainStatus,
                  ),
                  _HealthChip(
                    label: 'Último Log',
                    value: _lastLog != null
                        ? DateFormat(
                            'dd/MM/yyyy HH:mm',
                          ).format(_lastLog!.finishedAt ?? _lastLog!.startedAt)
                        : '—',
                    status: SybaseChainStatus.ok,
                  ),
                  const Tooltip(
                    message:
                        'Teste de restauração (full + logs) em ambiente de teste. '
                        'Pendente de implementação.',
                    child: _HealthChip(
                      label: 'Restore drill',
                      value: '—',
                      status: SybaseChainStatus.ok,
                    ),
                  ),
                  _ChainStatusChip(status: _chainStatus),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HealthChip extends StatelessWidget {
  const _HealthChip({
    required this.label,
    required this.value,
    required this.status,
  });

  final String label;
  final String value;
  final SybaseChainStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppPalette.databaseSybase.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppPalette.databaseSybase.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: FluentTheme.of(context).typography.body,
          ),
          Text(
            value,
            style: FluentTheme.of(context).typography.bodyStrong,
          ),
        ],
      ),
    );
  }
}

class _ChainStatusChip extends StatelessWidget {
  const _ChainStatusChip({required this.status});

  final SybaseChainStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (icon, color, text) = switch (status) {
      SybaseChainStatus.ok => (
        FluentIcons.check_mark,
        colors.success,
        'Cadeia OK',
      ),
      SybaseChainStatus.warning => (
        FluentIcons.warning,
        colors.warning,
        'Full expirado',
      ),
      SybaseChainStatus.broken => (
        FluentIcons.error,
        colors.danger,
        'Sem base full',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: FluentTheme.of(context).typography.bodyStrong?.copyWith(
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
