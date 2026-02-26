import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/services/i_metrics_analysis_service.dart';
import 'package:fluent_ui/fluent_ui.dart';

class MetricsPercentilesCard extends StatelessWidget {
  const MetricsPercentilesCard({
    required this.report,
    super.key,
  });

  final BackupMetricsReport report;

  @override
  Widget build(BuildContext context) {
    final percentiles = report.percentilesByType;
    if (percentiles.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = FluentTheme.of(context);
    final typography = theme.typography;

    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Métricas de performance (p50 / p95)',
            style: typography.title,
          ),
          const SizedBox(height: 4),
          Text(
            'Últimos 30 dias · ${_formatDate(report.startDate)} – ${_formatDate(report.endDate)}',
            style: typography.caption,
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              columnWidths: const {
                0: FixedColumnWidth(100),
                1: FixedColumnWidth(48),
                2: FixedColumnWidth(90),
                3: FixedColumnWidth(90),
                4: FixedColumnWidth(90),
                5: FixedColumnWidth(90),
                6: FixedColumnWidth(90),
                7: FixedColumnWidth(90),
              },
              border: TableBorder.all(color: AppColors.grey600.withValues(alpha: 0.5)),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: theme.brightness.isDark
                        ? theme.resources.cardBackgroundFillColorDefault
                        : theme.resources.subtleFillColorSecondary,
                  ),
                  children: [
                    _headerCell(context, 'Tipo'),
                    _headerCell(context, 'N'),
                    _headerCell(context, 'P50 Duração'),
                    _headerCell(context, 'P95 Duração'),
                    _headerCell(context, 'P50 Tamanho'),
                    _headerCell(context, 'P95 Tamanho'),
                    _headerCell(context, 'P50 Veloc.'),
                    _headerCell(context, 'P95 Veloc.'),
                  ],
                ),
                ...percentiles.entries.map(
                  (e) => _percentileRow(context, e.key, e.value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text,
        style: FluentTheme.of(context).typography.bodyStrong,
      ),
    );
  }

  TableRow _percentileRow(
    BuildContext context,
    BackupType backupType,
    BackupMetricsPercentiles p,
  ) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            backupType.displayName,
            style: FluentTheme.of(context).typography.body,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text('${p.sampleCount}', style: FluentTheme.of(context).typography.body),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            _formatDuration(p.p50DurationSeconds),
            style: FluentTheme.of(context).typography.body,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            _formatDuration(p.p95DurationSeconds),
            style: FluentTheme.of(context).typography.body,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            _formatSize(p.p50SizeBytes),
            style: FluentTheme.of(context).typography.body,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            _formatSize(p.p95SizeBytes),
            style: FluentTheme.of(context).typography.body,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            _formatSpeed(p.p50SpeedMbPerSec),
            style: FluentTheme.of(context).typography.body,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            _formatSpeed(p.p95SpeedMbPerSec),
            style: FluentTheme.of(context).typography.body,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (s == 0) return '${m}min';
    return '${m}min ${s}s';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatSpeed(double mbPerSec) {
    if (mbPerSec <= 0) return '–';
    return '${mbPerSec.toStringAsFixed(2)} MB/s';
  }
}
