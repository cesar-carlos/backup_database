/// Parâmetros centralizados de timeout e polling para operações do serviço.
class WindowsServiceTimingConfig {
  const WindowsServiceTimingConfig({
    this.shortTimeout = const Duration(seconds: 10),
    this.longTimeout = const Duration(seconds: 30),
    this.elevatedInstallTimeout = const Duration(seconds: 90),
    this.uacPromptTimeout = const Duration(minutes: 2),
    this.serviceDelay = const Duration(seconds: 2),
    this.startPollingInterval = const Duration(seconds: 1),
    this.startPollingTimeout = const Duration(seconds: 30),
    this.startPollingInitialDelay = const Duration(seconds: 3),
    this.retryMaxAttempts = 3,
    this.retryInitialDelay = const Duration(milliseconds: 500),
    this.retryBackoffMultiplier = 2,
    this.nssmCantOpenRetryDelay = const Duration(seconds: 2),
  });

  final Duration shortTimeout;
  final Duration longTimeout;

  /// Timeout dedicado para o script PowerShell elevado de instalação. O
  /// script faz `nssm install` + ~10 chamadas `nssm set` + `Start-Sleep`s,
  /// somando ~20-40s no caminho feliz e mais que isso em retries de
  /// "Can't open service". Manter `longTimeout` (30s) aqui causava
  /// cancelamentos com o script ainda em execução, deixando o serviço
  /// parcialmente configurado.
  final Duration elevatedInstallTimeout;

  /// Espera pelo prompt UAC (o utilizador pode demorar a clicar). Separado
  /// da execução do script elevado para não matar o filho a meio.
  final Duration uacPromptTimeout;
  final Duration serviceDelay;
  final Duration startPollingInterval;
  final Duration startPollingTimeout;
  final Duration startPollingInitialDelay;
  final int retryMaxAttempts;
  final Duration retryInitialDelay;
  final int retryBackoffMultiplier;

  /// Intervalo entre tentativas de `nssm set` quando o SCM ainda devolve
  /// `Can't open service` (serviço recém-criado).
  final Duration nssmCantOpenRetryDelay;

  static const WindowsServiceTimingConfig defaultConfig =
      WindowsServiceTimingConfig();
}
