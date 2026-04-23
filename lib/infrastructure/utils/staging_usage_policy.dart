/// Limites operacionais do diretorio de staging remoto (PR-4 / M5.3).
///
/// Valores alinhados ao plano: alerta a partir de 5 GiB, bloqueio de novos
/// backups a partir de 10 GiB.
class StagingUsagePolicy {
  StagingUsagePolicy._();

  static const int warnThresholdBytes = 5 * 1024 * 1024 * 1024;
  static const int blockThresholdBytes = 10 * 1024 * 1024 * 1024;

  static StagingUsageLevel levelFor(int bytes) {
    if (bytes < 0) {
      return StagingUsageLevel.ok;
    }
    if (bytes >= blockThresholdBytes) {
      return StagingUsageLevel.block;
    }
    if (bytes >= warnThresholdBytes) {
      return StagingUsageLevel.warn;
    }
    return StagingUsageLevel.ok;
  }

  static bool shouldBlock(int bytes) => levelFor(bytes) == StagingUsageLevel.block;
}

enum StagingUsageLevel {
  ok,
  warn,
  block,
}
