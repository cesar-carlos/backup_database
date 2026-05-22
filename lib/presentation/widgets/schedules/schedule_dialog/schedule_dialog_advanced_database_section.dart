import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_section_title.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ScheduleDialogSqlServerAdvancedPerformanceSection
    extends StatelessWidget {
  const ScheduleDialogSqlServerAdvancedPerformanceSection({
    required this.compression,
    required this.onCompressionChanged,
    required this.maxTransferSize,
    required this.onMaxTransferSizeChanged,
    required this.bufferCount,
    required this.onBufferCountChanged,
    required this.statsPercent,
    required this.onStatsPercentChanged,
    required this.stripingCount,
    required this.onStripingCountChanged,
    super.key,
  });

  final bool compression;
  final ValueChanged<bool> onCompressionChanged;
  final int? maxTransferSize;
  final ValueChanged<int> onMaxTransferSizeChanged;
  final int? bufferCount;
  final ValueChanged<int> onBufferCountChanged;
  final int statsPercent;
  final ValueChanged<int> onStatsPercentChanged;
  final int stripingCount;
  final ValueChanged<int> onStripingCountChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScheduleDialogSectionTitle('Performance Avançada (SQL Server)'),
        const SizedBox(height: 12),
        InfoLabel(
          label: 'Compressão Nativa (COMPRESSION)',
          child: ToggleSwitch(
            checked: compression,
            onChanged: onCompressionChanged,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Compressão nativa do SQL Server. Requer edição Enterprise do SQL Server 2008+.',
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        AppDropdown<int?>(
          label: 'Tamanho Máximo de Transferência (MAXTRANSFERSIZE)',
          value: maxTransferSize,
          placeholder: const Text('Usar padrão do SQL Server'),
          items: const [
            ComboBoxItem<int?>(child: Text('Usar padrão')),
            ComboBoxItem<int?>(value: 4194304, child: Text('4 MB')),
            ComboBoxItem<int?>(value: 16777216, child: Text('16 MB')),
            ComboBoxItem<int?>(value: 67108864, child: Text('64 MB')),
          ],
          onChanged: (int? value) {
            onMaxTransferSizeChanged(value ?? 4194304);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Tamanho máximo de transferência em bytes. Múltiplo de 64KB.',
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        AppDropdown<int?>(
          label: 'Buffer Count (BUFFERCOUNT)',
          value: bufferCount,
          placeholder: const Text('Usar padrão do SQL Server'),
          items: const [
            ComboBoxItem<int?>(child: Text('Usar padrão')),
            ComboBoxItem<int?>(value: 50, child: Text('50')),
            ComboBoxItem<int?>(value: 100, child: Text('100')),
            ComboBoxItem<int?>(value: 200, child: Text('200')),
          ],
          onChanged: (int? value) {
            onBufferCountChanged(value ?? 10);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Número de buffers de I/O. Valores altos podem causar consumo excessivo de memória.',
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        AppDropdown<int>(
          label: 'STATS Percentual',
          value: statsPercent,
          placeholder: const Text('10%'),
          items: const [
            ComboBoxItem<int>(value: 1, child: Text('1%')),
            ComboBoxItem<int>(value: 5, child: Text('5%')),
            ComboBoxItem<int>(value: 10, child: Text('10%')),
          ],
          onChanged: (int? value) {
            onStatsPercentChanged(value ?? 10);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Porcentagem de progresso para exibir. O SQL Server relata progresso a cada X%.',
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        AppDropdown<int>(
          label: 'Striping (arquivos paralelos)',
          value: stripingCount,
          placeholder: const Text('1 (sem striping)'),
          items: const [
            ComboBoxItem<int>(value: 1, child: Text('1 (sem striping)')),
            ComboBoxItem<int>(value: 2, child: Text('2 arquivos')),
            ComboBoxItem<int>(value: 3, child: Text('3 arquivos')),
            ComboBoxItem<int>(value: 4, child: Text('4 arquivos')),
          ],
          onChanged: (int? value) {
            onStripingCountChanged(value ?? 1);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Distribui o backup em N arquivos `<base>.partXofN.bak` que o '
          'SQL Server escreve em paralelo. Pode aumentar throughput em '
          'discos rápidos. Aplicado apenas a backups Full e Differential '
          '(Log permanece com 1 arquivo).',
          style: FluentTheme.of(context).typography.caption,
        ),
      ],
    );
  }
}

class ScheduleDialogSybaseAdvancedPerformanceSection extends StatelessWidget {
  const ScheduleDialogSybaseAdvancedPerformanceSection({
    required this.checkpointLog,
    required this.onCheckpointLogChanged,
    required this.serverSide,
    required this.onServerSideChanged,
    required this.autoTuneWriters,
    required this.onAutoTuneWritersChanged,
    required this.blockSize,
    required this.onBlockSizeChanged,
    super.key,
  });

  final SybaseCheckpointLog? checkpointLog;
  final ValueChanged<SybaseCheckpointLog?> onCheckpointLogChanged;
  final bool serverSide;
  final ValueChanged<bool> onServerSideChanged;
  final bool autoTuneWriters;
  final ValueChanged<bool> onAutoTuneWritersChanged;
  final int? blockSize;
  final ValueChanged<int?> onBlockSizeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScheduleDialogSectionTitle('Performance Avançada (Sybase)'),
        const SizedBox(height: 12),
        AppDropdown<SybaseCheckpointLog?>(
          label: 'CHECKPOINT LOG (backup Full)',
          value: checkpointLog,
          placeholder: const Text('Padrão do servidor'),
          items: const [
            ComboBoxItem<SybaseCheckpointLog?>(child: Text('Padrão')),
            ComboBoxItem<SybaseCheckpointLog?>(
              value: SybaseCheckpointLog.copy,
              child: Text('COPY'),
            ),
            ComboBoxItem<SybaseCheckpointLog?>(
              value: SybaseCheckpointLog.nocopy,
              child: Text('NOCOPY'),
            ),
            ComboBoxItem<SybaseCheckpointLog?>(
              value: SybaseCheckpointLog.auto,
              child: Text('AUTO'),
            ),
            ComboBoxItem<SybaseCheckpointLog?>(
              value: SybaseCheckpointLog.recover,
              child: Text('RECOVER'),
            ),
          ],
          onChanged: onCheckpointLogChanged,
        ),
        const SizedBox(height: 8),
        Text(
          'COPY: mais rápido no restore; NOCOPY: backup menor. Apenas para backup Full.',
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Modo Server-Side (dbbackup -s)',
          child: ToggleSwitch(
            checked: serverSide,
            onChanged: onServerSideChanged,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Backup gerado no servidor. Aplica-se quando dbbackup é usado.',
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'AUTO TUNE WRITERS',
          child: ToggleSwitch(
            checked: autoTuneWriters,
            onChanged: onAutoTuneWritersChanged,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ajuste automático de threads de escrita. Recomendado em ambientes I/O-bound.',
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        AppDropdown<int?>(
          label: 'Block Size (dbbackup -b)',
          value: blockSize,
          placeholder: const Text('Padrão (128 páginas)'),
          items: const [
            ComboBoxItem<int?>(child: Text('Padrão')),
            ComboBoxItem<int?>(value: 64, child: Text('64')),
            ComboBoxItem<int?>(value: 128, child: Text('128')),
            ComboBoxItem<int?>(value: 256, child: Text('256')),
            ComboBoxItem<int?>(value: 512, child: Text('512')),
          ],
          onChanged: onBlockSizeChanged,
        ),
        const SizedBox(height: 8),
        Text(
          'Tamanho do bloco em páginas. Valores maiores podem melhorar throughput.',
          style: FluentTheme.of(context).typography.caption,
        ),
      ],
    );
  }
}

/// **Organism** — read-only summary of the selected Firebird connection
/// (embedded, service manager, version hint, encryption key) in
/// ScheduleDialog.
class ScheduleDialogFirebirdAdvancedSummarySection extends StatelessWidget {
  const ScheduleDialogFirebirdAdvancedSummarySection({
    required this.config,
    super.key,
  });

  final FirebirdConfig? config;

  static String _serviceManagerLabel(FirebirdServiceManagerMode mode) {
    return switch (mode) {
      FirebirdServiceManagerMode.auto => 'Automático',
      FirebirdServiceManagerMode.always => 'Sempre (service manager)',
      FirebirdServiceManagerMode.never => 'Nunca (ficheiros diretos)',
    };
  }

  static String _serverVersionHintLabel(FirebirdServerVersionHint hint) {
    return switch (hint) {
      FirebirdServerVersionHint.auto => 'Automático',
      FirebirdServerVersionHint.v25 => 'Firebird 2.5',
      FirebirdServerVersionHint.v30 => 'Firebird 3.0',
      FirebirdServerVersionHint.v40 => 'Firebird 4.0',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScheduleDialogSectionTitle('Firebird'),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        if (c == null) ...[
          const InfoBar(
            title: Text('Nenhuma configuração selecionada'),
            content: Text(
              'Escolha uma configuração Firebird no separador Geral para '
              'ver o resumo das opções avançadas da ligação.',
            ),
            severity: InfoBarSeverity.warning,
          ),
        ] else ...[
          Text(
            'Estas opções vêm da configuração de base de dados; edite-as no '
            'diálogo de configuração Firebird.',
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          InfoLabel(
            label: 'Modo embedded',
            child: Text(c.useEmbedded ? 'Sim' : 'Não'),
          ),
          const SizedBox(height: AppSpacing.sm),
          InfoLabel(
            label: 'Service manager (gbak / nbackup)',
            child: Text(_serviceManagerLabel(c.serviceManagerMode)),
          ),
          const SizedBox(height: AppSpacing.sm),
          InfoLabel(
            label: 'Versão do servidor (sugestão)',
            child: Text(_serverVersionHintLabel(c.serverVersionHint)),
          ),
          const SizedBox(height: AppSpacing.sm),
          InfoLabel(
            label: 'Chave de criptografia',
            child: Text(
              c.cryptKey.trim().isEmpty ? 'Não definida' : 'Definida',
            ),
          ),
        ],
      ],
    );
  }
}

class ScheduleDialogAdvancedDatabaseSection {
  ScheduleDialogAdvancedDatabaseSection._();

  static Widget build({
    required DatabaseType databaseType,
    required Widget Function() sqlServerAdvancedBuilder,
    required Widget Function() sybaseAdvancedBuilder,
    required Widget Function() firebirdAdvancedBuilder,
  }) {
    return switch (databaseType) {
      DatabaseType.sqlServer => sqlServerAdvancedBuilder(),
      DatabaseType.sybase => sybaseAdvancedBuilder(),
      DatabaseType.postgresql => const SizedBox.shrink(),
      DatabaseType.firebird => firebirdAdvancedBuilder(),
    };
  }
}
