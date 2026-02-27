import 'package:backup_database/core/constants/backup_constants.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

enum SybaseChainStatus { ok, warning, broken }

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
    _loadHealth();
  }

  Future<void> _loadHealth() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = GetIt.instance<IBackupHistoryRepository>();
      final result = await repo.getAll(limit: 200);

      result.fold(
        (backups) {
          final sybase = backups
              .where((b) => b.databaseType.toLowerCase() == 'sybase')
              .toList();

          final successfulFulls = sybase
              .where(
                (b) =>
                    (b.backupType == BackupType.full.name ||
                        b.backupType == BackupType.fullSingle.name) &&
                    b.status == BackupStatus.success,
              )
              .toList();
          successfulFulls.sort(
            (a, b) =>
                (b.finishedAt ?? b.startedAt)
                    .compareTo(a.finishedAt ?? a.startedAt),
          );
          final lastFull = successfulFulls.isNotEmpty ? successfulFulls.first : null;

          final successfulLogs = sybase
              .where(
                (b) =>
                    b.backupType == BackupType.log.name &&
                    b.status == BackupStatus.success,
              )
              .toList();
          successfulLogs.sort(
            (a, b) =>
                (b.finishedAt ?? b.startedAt)
                    .compareTo(a.finishedAt ?? a.startedAt),
          );
          final lastLog = successfulLogs.isNotEmpty ? successfulLogs.first : null;

          final lastBackup = sybase.isNotEmpty
              ? sybase.reduce(
                  (a, b) =>
                      (a.finishedAt ?? a.startedAt)
                              .isAfter(b.finishedAt ?? b.startedAt)
                          ? a
                          : b,
                )
              : null;

          var status = SybaseChainStatus.ok;
          if (lastFull == null && lastLog != null) {
            status = SybaseChainStatus.broken;
          } else if (lastFull != null) {
            final daysSinceFull =
                DateTime.now().difference(lastFull.finishedAt ?? lastFull.startedAt).inDays;
            if (daysSinceFull > BackupConstants.maxDaysForLogBackupBaseFull) {
              status = SybaseChainStatus.warning;
            }
            if (lastBackup?.status == BackupStatus.error) {
              status = status == SybaseChainStatus.ok
                  ? SybaseChainStatus.warning
                  : status;
            }
          }

          if (mounted) {
            setState(() {
              _lastFull = lastFull;
              _lastLog = lastLog;
              _chainStatus = status;
              _isLoading = false;
            });
          }
        },
        (failure) {
          if (mounted) {
            setState(() {
              _error = failure.toString();
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
                      color: AppColors.error,
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
                        ? DateFormat('dd/MM/yyyy HH:mm')
                            .format(_lastFull!.finishedAt ?? _lastFull!.startedAt)
                        : '—',
                    status: _chainStatus,
                  ),
                  _HealthChip(
                    label: 'Último Log',
                    value: _lastLog != null
                        ? DateFormat('dd/MM/yyyy HH:mm')
                            .format(_lastLog!.finishedAt ?? _lastLog!.startedAt)
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
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
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
    final (icon, color, text) = switch (status) {
      SybaseChainStatus.ok => (
        FluentIcons.check_mark,
        AppColors.success,
        'Cadeia OK',
      ),
      SybaseChainStatus.warning => (
        FluentIcons.warning,
        AppColors.warning,
        'Full expirado',
      ),
      SybaseChainStatus.broken => (
        FluentIcons.error,
        AppColors.error,
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
