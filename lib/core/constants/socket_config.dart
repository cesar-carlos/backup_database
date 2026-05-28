class SocketConfig {
  SocketConfig._();

  static const int defaultPort = 9527;
  static const int chunkSize = 131072; // 128KB
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration heartbeatTimeout = Duration(seconds: 60);
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration scheduleRequestTimeout = Duration(seconds: 15);

  /// §audit-2026-05-28 wave 3 (P1): timeout **legado** de file transfer
  /// — era usado como um único "deadline total" de 5 min, o que abortava
  /// transferências grandes (>2 GB em links de 100 Mbps típicos) mesmo
  /// quando estavam progredindo normalmente. Hoje a transferência usa:
  ///
  ///   - [fileTransferIdleTimeout] como **watchdog de inatividade**
  ///     (zerado a cada chunk / progress recebido);
  ///   - [fileTransferHardTimeout] como teto absoluto (defesa contra
  ///     transferência presa progredindo bytes minúsculos por horas).
  ///
  /// A constante continua exportada por compatibilidade — callers
  /// novos devem usar os helpers acima.
  static const Duration fileTransferTimeout = Duration(minutes: 5);

  /// Inatividade máxima permitida durante um file transfer (sem
  /// chunk/progress recebido). Cada `fileChunk` ou
  /// `fileTransferProgress` reseta o watchdog. Backups que ficam mudos
  /// por mais que isso indicam servidor travado / rede caída / disco
  /// cheio do peer.
  ///
  /// 2 min cobre folgadamente um GC pausado / IO lento, sem deixar o
  /// cliente preso por horas sem evidência.
  static const Duration fileTransferIdleTimeout = Duration(minutes: 2);

  /// Teto absoluto: mesmo que o servidor mande 1 byte/segundo, a
  /// transferência termina aqui. Dimensionado para suportar **40 GB
  /// em link de 30 Mbps** (~3 h) com folga. Backups maiores são
  /// excepcionais; quando ocorrerem, é melhor abortar e logar para
  /// investigação do que vazar handle aberto indefinidamente.
  static const Duration fileTransferHardTimeout = Duration(hours: 6);

  static const Duration backupExecutionTimeout = Duration(minutes: 10);
  static const int maxRetries = 3;
  static const int maxReconnectAttempts = 5;

  // Retry configuration for downloads
  static const Duration downloadRetryInitialDelay = Duration(seconds: 2);
  static const Duration downloadRetryMaxDelay = Duration(seconds: 30);
  static const int downloadRetryBackoffMultiplier = 2;

  // Limites de proteção contra peers maliciosos / dados malformados.
  // [maxMessagePayloadBytes] limita o `length` declarado em cada header
  // para evitar OOM quando o peer envia um valor absurdo (ex.: 4 GB).
  // [maxBufferOverhead] é a folga máxima permitida no buffer de leitura
  // antes de cortar a conexão (peer envia dados sem cabeçalho válido).
  static const int maxMessagePayloadBytes = 64 * 1024 * 1024; // 64 MB
  static const int maxBufferOverhead = 128 * 1024 * 1024; // 128 MB
}
