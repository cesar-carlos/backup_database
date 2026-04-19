/// Helpers de formatação de bytes e cálculo de throughput compartilhados
/// pelos serviços de backup. Centralizam o que antes estava duplicado em
/// `SqlServerBackupService`, `SybaseBackupService`, `PostgresBackupService`
/// e `BackupOrchestratorService`.
class ByteFormat {
  ByteFormat._();

  static const int _kb = 1024;
  static const int _mb = 1024 * 1024;
  static const int _gb = 1024 * 1024 * 1024;

  /// Formata `bytes` em uma string legível (B/KB/MB/GB).
  static String format(int bytes) {
    if (bytes < _kb) return '$bytes B';
    if (bytes < _mb) return '${(bytes / _kb).toStringAsFixed(2)} KB';
    if (bytes < _gb) return '${(bytes / _mb).toStringAsFixed(2)} MB';
    return '${(bytes / _gb).toStringAsFixed(2)} GB';
  }

  /// Calcula a velocidade média de transferência em MB/s.
  ///
  /// Retorna `0` quando `durationSeconds <= 0` para evitar divisão por zero.
  static double speedMbPerSec(int sizeInBytes, int durationSeconds) {
    if (durationSeconds <= 0) return 0;
    final sizeInMb = sizeInBytes / _mb;
    return sizeInMb / durationSeconds;
  }

  /// Variação que aceita um [Duration] já calculado.
  static double speedMbPerSecFromDuration(int sizeInBytes, Duration duration) {
    return speedMbPerSec(sizeInBytes, duration.inSeconds);
  }
}
