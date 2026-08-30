import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';

/// Normaliza `backupType` para um valor valido apos troca de SGBD.
///
/// Devolve o **mesmo tipo** se o SGBD suportar (preserva escolha do
/// utilizador). So coage para `full` quando o tipo nao se aplica:
/// - Nao-postgres / nao-firebird nao suportam `fullSingle`
/// - Sybase nao suporta `differential` na UI (apenas full / log).
/// - Firebird ja oferece Full / Full Single / Diferencial / Log na
///   UI; `convertedFullSingle` (vindo de import legado) cai para
///   `fullSingle` pois e o equivalente direto na ferramenta gbak.
/// - `convertedDifferential` / `convertedLog` ficam preservados para
///   Firebird/Postgres porque a regra do strategy aceita.
///
/// Esta funcao **NAO** deve ser chamada no `_save()` — ali o tipo ja
/// foi escolhido pelo utilizador e nao deve ser reescrito silenciosamente
/// (caso contrario, agendamento incremental existente vira full no
/// proximo save, perdendo a cadeia).
BackupType normalizeBackupTypeForDatabase(
  DatabaseType databaseType,
  BackupType backupType,
) {
  if (databaseType != DatabaseType.postgresql &&
      databaseType != DatabaseType.firebird &&
      backupType == BackupType.fullSingle) {
    return BackupType.full;
  }
  if (databaseType == DatabaseType.sybase &&
      backupType == BackupType.differential) {
    return BackupType.full;
  }
  if (databaseType == DatabaseType.firebird &&
      backupType == BackupType.convertedFullSingle) {
    return BackupType.fullSingle;
  }
  return backupType;
}
