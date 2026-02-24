class ScheduleDialogStrings {
  ScheduleDialogStrings._();

  static const String newSchedule = 'Novo Agendamento';
  static const String editSchedule = 'Editar Agendamento';
  static const String tabGeneral = 'Geral';
  static const String tabSettings = 'Configurações';
  static const String tabScriptSql = 'Script SQL';

  static const String scheduleName = 'Nome do Agendamento';
  static const String scheduleNameHint = 'Ex: Backup Diário Produção';
  static const String database = 'Banco de Dados';
  static const String databaseType = 'Tipo de Banco';
  static const String databaseTypePlaceholder = 'Tipo de Banco';

  static const String destinations = 'Destinos';
  static const String backupFolderSection = 'Pasta de Backup';
  static const String backupFolderLabel = 'Pasta para Armazenar Backup';
  static const String backupFolderHint = r'C:\Backups';
  static const String backupFolderRequired = 'Pasta de backup é obrigatória';
  static const String backupFolderDescription =
      'Pasta onde o arquivo de backup será gerado antes de enviar aos destinos';

  static const String options = 'Opções';
  static const String compressBackup = 'Compactar backup';
  static const String compressionFormat = 'Formato de compressão';
  static const String compressionFormatPlaceholder = 'Formato de compressão';
  static const String compressionFormatZip = 'ZIP (compressão rápida, menor taxa)';
  static const String compressionFormatRar = 'RAR (compressão maior, mais processamento)';
  static const String schedulingEnabled = 'Agendamento habilitado';

  static const String timeoutsSection = 'Timeouts (Segurança Operacional)';
  static const String backupTimeout = 'Timeout de Backup';
  static const String verifyTimeout = 'Timeout de Verificação';
  static const String minutes = 'Minutos';
  static const String max24Hours = 'Máximo: 24 horas';
  static const String timeoutsDescription =
      'Define o tempo máximo de espera para execução do backup e verificação de integridade. '
      'Zero significa espera infinita.';

  static const String cancel = 'Cancelar';
  static const String create = 'Criar';
  static const String save = 'Salvar';
}
