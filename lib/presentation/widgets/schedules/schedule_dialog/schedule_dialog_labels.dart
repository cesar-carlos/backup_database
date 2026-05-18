import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';

class ScheduleDialogLabels {
  ScheduleDialogLabels._();

  static String scheduleTypeName(ScheduleType type) {
    switch (type) {
      case ScheduleType.daily:
        return 'Diário';
      case ScheduleType.weekly:
        return 'Semanal';
      case ScheduleType.monthly:
        return 'Mensal';
      case ScheduleType.interval:
        return 'Por Intervalo';
    }
  }

  static String backupTypeDescription(
    DatabaseType databaseType,
    BackupType type,
  ) {
    if (databaseType == DatabaseType.postgresql) {
      switch (type) {
        case BackupType.full:
          return 'Backup físico completo usando pg_basebackup. Banco ONLINE. '
              'Inclui todos os bancos do cluster, dados, estrutura e catálogo.';
        case BackupType.fullSingle:
          return 'Backup lógico completo usando pg_dump. Banco ONLINE. '
              'Inclui apenas a base de dados especificada na configuração. '
              'Formato .backup.';
        case BackupType.log:
        case BackupType.convertedLog:
          return 'Captura de WAL para PITR usando pg_receivewal em modo '
              'one-shot (ate um LSN alvo). Pode usar replication slot dedicado '
              'quando habilitado por ambiente.';
        case BackupType.differential:
        case BackupType.convertedDifferential:
          return 'Backup incremental usando pg_basebackup. Requer backup FULL '
              'anterior com manifest. (PostgreSQL 17+)';
        case BackupType.convertedFullSingle:
          return 'Backup lógico completo usando pg_dump. Banco ONLINE. '
              'Inclui apenas a base de dados especificada na configuração. '
              'Formato .backup.';
      }
    }
    if (databaseType == DatabaseType.sybase) {
      switch (type) {
        case BackupType.full:
          return 'Backup completo do banco de dados via BACKUP DATABASE/dbbackup.';
        case BackupType.log:
        case BackupType.convertedLog:
          return 'Backup do log de transações. Pode ser executado frequentemente '
              'e requer backup Full anterior.';
        case BackupType.differential:
        case BackupType.convertedDifferential:
          return 'Sybase SQL Anywhere não suporta backup diferencial nativo; '
              'este tipo é convertido automaticamente para Incremental '
              '(Transaction Log).';
        case BackupType.fullSingle:
        case BackupType.convertedFullSingle:
          return 'Sybase trata este tipo como backup Full.';
      }
    }
    if (databaseType == DatabaseType.firebird) {
      switch (type) {
        case BackupType.full:
          return 'Backup fisico nivel 0 com nbackup (-B 0), ficheiro .nbk. '
              'Nao e um dump logico; chave AES na configuracao aplica-se apenas '
              'a Full Single (gbak). Firebird nao tem verify nativo; modo '
              'Strict pode usar restore temporario.';
        case BackupType.fullSingle:
        case BackupType.convertedFullSingle:
          return 'Backup logico completo com gbak (-b), ficheiro .fbk. '
              'Use este tipo para criptografia AES (-key) na configuracao '
              'Firebird.';
        case BackupType.log:
        case BackupType.convertedLog:
          return 'Firebird nao tem arquivamento de segmentos de log exportavel '
              'para PITR no estilo PostgreSQL. Na execucao, tipo Log e tratado '
              'como nbackup incremental (-B 1); o historico pode ser gravado '
              'como Diferencial. Requer cadeia nbackup nivel 0 previa. Para '
              'dump logico use Full Single (gbak).';
        case BackupType.differential:
        case BackupType.convertedDifferential:
          return 'Backup fisico incremental com nbackup (-B 1), ficheiro .nbk. '
              'Requer backup nivel 0 (-B 0) previo na mesma base; nao e um dump '
              'logico (use Full Single / gbak para .fbk).';
      }
    }
    switch (type) {
      case BackupType.full:
        return 'Backup completo do banco de dados. Base para backups '
            'diferenciais e logs.';
      case BackupType.fullSingle:
        return 'Backup completo de uma base de dados específica.';
      case BackupType.differential:
        return 'Backup apenas das alterações desde o último backup completo. '
            'Requer backup Full anterior.';
      case BackupType.log:
        return 'Backup do log de transações. Pode ser executado frequentemente. '
            'Requer backup Full anterior.';
      case BackupType.convertedDifferential:
        return 'Backup convertido de Differential para Full.';
      case BackupType.convertedFullSingle:
        return 'Backup convertido de Full Single para Full.';
      case BackupType.convertedLog:
        return 'Backup convertido de Log para Log.';
    }
  }
}
