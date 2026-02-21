/// Opções avançadas de performance e compressão para backup SQL Server.
/// Estas opções permitem tuning controlado de throughput do backup.
class SqlServerBackupOptions {
  const SqlServerBackupOptions({
    this.compression = false,
    this.maxTransferSize,
    this.bufferCount,
    this.blockSize,
    this.stripingCount = 1,
    this.statsPercent = 10,
  });

  /// Habilita compressão nativa do SQL Server (WITH COMPRESSION).
  /// Requer edição Enterprise ou superior do SQL Server 2008+.
  final bool compression;

  /// Número de arquivos para backup striping (1-4).
  /// Aumenta throughput distribuindo o backup em múltiplos arquivos.
  /// Valores típicos: 1 (sem striping), 2, 3, 4.
  final int stripingCount;

  /// Tamanho máximo de transferência em bytes (MAXTRANSFERSIZE).
  /// Deve ser múltiplo de 64KB (65536 bytes).
  /// Valores típicos: 4MB (4194304), 16MB (16777216), 64MB (67108864).
  /// Se null, usa o default do SQL Server.
  final int? maxTransferSize;

  /// Número de buffers para operação de I/O (BUFFERCOUNT).
  /// Controla o número de buffers de I/O usados pela operação de backup.
  /// Valores muito altos podem causar OOM (Out of Memory).
  /// Se null, usa o default do SQL Server.
  final int? bufferCount;

  /// Tamanho do bloco em bytes (BLOCKSIZE).
  /// Usado para operações avançadas de tuning.
  /// Se null, usa o default do SQL Server.
  final int? blockSize;

  /// Porcentagem de progresso para exibir (STATS).
  /// O SQL Server relata progresso a cada X% de conclusão.
  /// Valores comuns: 1, 5, 10. Default é 10.
  final int statsPercent;

  /// Verifica se as opções são válidas.
  ///
  /// Retorna `true` se todas as validações passarem.
  /// Retorna `false` e [errorMessage] se houver problemas.
  ({bool isValid, String? errorMessage}) validate() {
    final errors = <String>[];

    if (maxTransferSize != null) {
      if (maxTransferSize! < 65536) {
        errors.add('maxTransferSize deve ser pelo menos 64KB (65536 bytes)');
      }
      if (maxTransferSize! % 65536 != 0) {
        errors.add('maxTransferSize deve ser múltiplo de 64KB (65536 bytes)');
      }
      if (maxTransferSize! > 67108864) {
        errors.add('maxTransferSize não deve exceder 64MB (67108864 bytes)');
      }
    }

    if (bufferCount != null) {
      if (bufferCount! < 1) {
        errors.add('bufferCount deve ser maior que 0');
      }
      if (bufferCount! > 200) {
        errors.add('bufferCount não deve exceder 200 (risco de OOM)');
      }
    }

    if (blockSize != null) {
      if (blockSize! < 512) {
        errors.add('blockSize deve ser pelo menos 512 bytes');
      }
      if (blockSize! % 512 != 0) {
        errors.add('blockSize deve ser múltiplo de 512 bytes');
      }
      if (blockSize! > 65536) {
        errors.add('blockSize não deve exceder 64KB (65536 bytes)');
      }
    }

    if (statsPercent < 1 || statsPercent > 100) {
      errors.add('statsPercent deve estar entre 1 e 100');
    }

    if (stripingCount < 1) {
      errors.add('stripingCount deve ser pelo menos 1');
    }
    if (stripingCount > 4) {
      errors.add('stripingCount não deve exceder 4');
    }

    if (errors.isEmpty) {
      return (isValid: true, errorMessage: null);
    }


    return (isValid: false, errorMessage: errors.join('; '));
  }

  /// Valores padrão seguros para uso em produção.
  static const SqlServerBackupOptions safeDefaults = SqlServerBackupOptions(
    compression: false,
    maxTransferSize: 4194304, // 4MB
    statsPercent: 10,
  );

  /// Gera a cláusula WITH das opções não nulas para uso em SQL.
  String buildWithClause() {
    final clauses = <String>[];

    if (compression) {
      clauses.add('COMPRESSION');
    }

    if (maxTransferSize != null) {
      clauses.add('MAXTRANSFERSIZE = $maxTransferSize');
    }

    if (bufferCount != null) {
      clauses.add('BUFFERCOUNT = $bufferCount');
    }

    if (blockSize != null) {
      clauses.add('BLOCKSIZE = $blockSize');
    }

    if (clauses.isEmpty) {
      return '';
    }

    return '${clauses.join(', ')}, ';
  }

  @override
  String toString() =>
      'SqlServerBackupOptions('
      'compression: $compression, '
      'maxTransferSize: $maxTransferSize, '
      'bufferCount: $bufferCount, '
      'blockSize: $blockSize, '
      'stripingCount: $stripingCount, '
      'statsPercent: $statsPercent)';

  @override
  bool operator ==(Object other) =>
      other is SqlServerBackupOptions &&
      other.compression == compression &&
      other.maxTransferSize == maxTransferSize &&
      other.bufferCount == bufferCount &&
      other.blockSize == blockSize &&
      other.stripingCount == stripingCount &&
      other.statsPercent == statsPercent;

  @override
  int get hashCode =>
      compression.hashCode ^
      maxTransferSize.hashCode ^
      bufferCount.hashCode ^
      blockSize.hashCode ^
      stripingCount.hashCode ^
      statsPercent.hashCode;
}
