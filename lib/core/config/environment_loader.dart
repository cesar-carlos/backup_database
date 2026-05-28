import 'dart:io';

import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path/path.dart' as p;

enum EnvironmentSource { externalMachineFile, bundledAsset }

class EnvironmentLoadPlan {
  const EnvironmentLoadPlan({
    required this.source,
    required this.description,
    this.filePath,
  });

  final EnvironmentSource source;
  final String description;
  final String? filePath;
}

/// Resultado observable do carregamento do `.env`.
///
/// Em vez de devolver `Future<void>` e engolir falhas como warning, expomos
/// quais chaves obrigatórias estão faltando depois do load — assim o
/// bootstrap pode decidir se cabe fallback (`disabled`/`misconfigured`) ou
/// se a feature simplesmente loga e segue.
///
/// Usado por [EnvironmentLoader.loadIfNeeded] em combinação com
/// [EnvironmentLoader.requiredKeys] para detectar configurações órfãs.
class EnvironmentLoadOutcome {
  const EnvironmentLoadOutcome({
    required this.source,
    required this.sourceDescription,
    required this.loadedKeyCount,
    required this.missingRequiredKeys,
    required this.attemptedFallback,
    required this.dotenvInitialized,
    this.loadError,
    this.leakedBundledSecretKeys = const <String>{},
  });

  /// Origem efetiva do `.env` carregado (`externalMachineFile`,
  /// `bundledAsset`).
  final EnvironmentSource source;

  /// Descrição user-friendly da origem (path externo OU "asset bundled").
  final String sourceDescription;

  /// Quantidade de chaves não-vazias presentes em `dotenv.env`.
  final int loadedKeyCount;

  /// Chaves declaradas em [EnvironmentLoader.requiredKeys] que estão
  /// ausentes ou vazias após o load. Vazio = configuração saudável.
  final Set<String> missingRequiredKeys;

  /// True quando o load primário não satisfez as chaves obrigatórias e o
  /// fallback para o asset bundled foi acionado (informativo p/ logs).
  final bool attemptedFallback;

  /// True quando `dotenv.isInitialized == true` após o load (mesmo que
  /// algumas chaves obrigatórias ainda estejam faltando). Falso = falha
  /// catastrófica — consumidores devem tratar como `dotenv inacessível`.
  final bool dotenvInitialized;

  /// Erro capturado, se houver (último observado em load primário ou
  /// fallback). Mantido como referência para diagnóstico.
  final Object? loadError;

  /// Chaves listadas em [EnvironmentLoader.forbiddenInBundledAssetKeys]
  /// que vieram **com valor não vazio** do asset bundled. O loader
  /// limpa esses valores antes de retornar, mas mantém a lista aqui
  /// para que o bootstrap possa registrar incidente / quebrar build.
  final Set<String> leakedBundledSecretKeys;

  /// Configuração saudável: dotenv inicializado, nenhuma chave crítica
  /// faltando e nenhum segredo vazado no bundle.
  bool get isHealthy =>
      dotenvInitialized &&
      missingRequiredKeys.isEmpty &&
      leakedBundledSecretKeys.isEmpty;
}

/// Centraliza o carregamento do `.env`.
///
/// Em Windows instalado, a prioridade agora e o arquivo externo em
/// `C:\ProgramData\BackupDatabase\config\.env`. Em desenvolvimento local,
/// ou quando o arquivo externo ainda nao existe, o fallback continua sendo
/// o asset `.env` empacotado para `flutter run`.
///
/// **Defesa em profundidade** (audit 2026-05-28):
/// - `requiredKeys` lista as chaves cuja ausência inviabiliza features
///   críticas (atualmente: `AUTO_UPDATE_FEED_URL`).
/// - Se o arquivo externo for carregado mas alguma `requiredKey` estiver
///   ausente/vazia, [loadIfNeeded] tenta automaticamente o asset bundled
///   como fallback (`dotenv.load`) — útil quando o `.env` em ProgramData
///   foi parcialmente escrito por uma corrida do `merge_env.ps1` ou ainda
///   não recebeu chaves adicionadas em `.env.example`.
/// - O [EnvironmentLoadOutcome] retornado expõe diagnósticos para que o
///   bootstrap possa registrar/exibir o estado ao operador.
/// - Mensagens de falha agora vão como `error` (não `warning`), garantindo
///   que apareçam mesmo em logs filtrados por severidade.
class EnvironmentLoader {
  EnvironmentLoader._();

  static const String bundledAssetFileName = '.env';
  static const String migratedBackupFileName = '.env.migrated-from-appdir.bak';

  /// Chaves de ambiente cuja ausência impacta features críticas do
  /// produto. Quando alguma delas faltar após o load primário, o loader
  /// dispara fallback para o asset bundled antes de seguir.
  ///
  /// **Não adicione aqui chaves opcionais** — apenas as que travariam
  /// uma feature inteira no boot.
  static const Set<String> requiredKeys = <String>{'AUTO_UPDATE_FEED_URL'};

  /// Chaves cuja **presença** no asset bundled é proibida — vazá-las em
  /// `flutter_assets/.env` é um leak crítico (chave privada Ed25519 de
  /// licença, hash da senha admin, credenciais de teste FTP, etc).
  ///
  /// O guard `_scrubLeakedSecretsFromCurrentEnv` roda no fim de
  /// [loadIfNeeded] e:
  /// 1. Loga `error` com a chave culpada (capturado em CI / observabilidade).
  /// 2. **Limpa** o valor de `dotenv.env` para não vazá-lo em runtime.
  /// 3. Marca o outcome com `leakedBundledSecretKeys`.
  ///
  /// Valores reais devem vir EXCLUSIVAMENTE do arquivo externo em
  /// `C:\ProgramData\BackupDatabase\config\.env` (ou env vars do SO).
  static const Set<String> forbiddenInBundledAssetKeys = <String>{
    'BACKUP_DATABASE_LICENSE_PRIVATE_KEY',
    'LICENSE_ADMIN_PASSWORD',
    'LICENSE_ADMIN_PASSWORD_HASH',
    'FTP_IT_PASS',
  };

  /// Hook substituível para testes — leitura do asset bundled.
  ///
  /// Em runtime real, o consumer (`AppBootstrap`) injeta uma função que
  /// delega para `rootBundle.loadString('.env')`. Mantemos a indireção
  /// para evitar dependência hard de `package:flutter/services.dart`
  /// dentro do `EnvironmentLoader` (que precisa rodar em testes Dart
  /// puros sem TestWidgetsFlutterBinding).
  static Future<String> Function(String key)? bundledAssetReader;

  static EnvironmentLoadPlan resolveLoadPlan({
    required bool isWindows,
    required bool externalFileExists,
    String? externalFilePath,
  }) {
    if (isWindows && externalFileExists && externalFilePath != null) {
      return EnvironmentLoadPlan(
        source: EnvironmentSource.externalMachineFile,
        filePath: externalFilePath,
        description: externalFilePath,
      );
    }

    return const EnvironmentLoadPlan(
      source: EnvironmentSource.bundledAsset,
      description: bundledAssetFileName,
    );
  }

  static File resolveLegacyInstalledEnvironmentFile({
    String? executablePath,
  }) {
    final resolvedExecutable = executablePath ?? Platform.resolvedExecutable;
    final appDir = File(resolvedExecutable).parent.path;
    return File(p.join(appDir, bundledAssetFileName));
  }

  static Future<bool> migrateLegacyWindowsEnvironmentIfNeeded({
    required bool isWindows,
    required File externalEnvFile,
    required File legacyEnvFile,
    String? logPrefix,
  }) async {
    if (!isWindows ||
        await externalEnvFile.exists() ||
        !await legacyEnvFile.exists()) {
      return false;
    }

    await externalEnvFile.parent.create(recursive: true);
    await legacyEnvFile.copy(externalEnvFile.path);

    final backupFile = File(
      p.join(externalEnvFile.parent.path, migratedBackupFileName),
    );
    if (!await backupFile.exists()) {
      await legacyEnvFile.copy(backupFile.path);
    }

    LoggerService.info(
      '${logPrefix ?? '[env]'} arquivo legado migrado de '
      '${legacyEnvFile.path} para ${externalEnvFile.path}',
    );
    return true;
  }

  /// Carrega o arquivo `.env` se ainda nao foi carregado e devolve um
  /// [EnvironmentLoadOutcome] descrevendo o estado final (origem efetiva,
  /// chaves obrigatórias faltando, se houve fallback, etc.).
  ///
  /// **Nunca lança** — falhas são reportadas via `outcome.loadError` e
  /// logs `error` (não mais `warning`, que ficava perdido entre milhares
  /// de linhas).
  static Future<EnvironmentLoadOutcome> loadIfNeeded({
    String? logPrefix,
  }) async {
    final prefix = logPrefix ?? '[env]';

    if (dotenv.isInitialized) {
      LoggerService.debug('$prefix variaveis ja carregadas (skip)');
      return _buildOutcome(
        source: EnvironmentSource.externalMachineFile,
        sourceDescription: '(already initialized)',
        attemptedFallback: false,
      );
    }

    Object? primaryError;
    EnvironmentLoadPlan? loadPlan;
    final leakedSecretKeys = <String>{};

    try {
      final externalEnvFile = await resolveMachineEnvironmentFile();
      await migrateLegacyWindowsEnvironmentIfNeeded(
        isWindows: Platform.isWindows,
        externalEnvFile: externalEnvFile,
        legacyEnvFile: resolveLegacyInstalledEnvironmentFile(),
        logPrefix: prefix,
      );
      loadPlan = resolveLoadPlan(
        isWindows: Platform.isWindows,
        externalFileExists: await externalEnvFile.exists(),
        externalFilePath: externalEnvFile.path,
      );

      switch (loadPlan.source) {
        case EnvironmentSource.externalMachineFile:
          final envText = await File(loadPlan.filePath!).readAsString();
          dotenv.loadFromString(envString: envText);
        case EnvironmentSource.bundledAsset:
          await _loadBundledAsset();
      }

      LoggerService.info(
        '$prefix variaveis de ambiente carregadas de '
        '${loadPlan.description} (chaves=${dotenv.env.length})',
      );

      // Quando a origem primária é o asset bundled, valida que nenhum
      // segredo foi inadvertidamente comitado lá — proteção contra
      // regressão do incidente que motivou esse guard.
      if (loadPlan.source == EnvironmentSource.bundledAsset) {
        _scrubLeakedSecretsFromCurrentEnv(
          leakedKeys: leakedSecretKeys,
          source: 'bundled asset',
          logPrefix: prefix,
        );
      }
    } on Object catch (e, s) {
      primaryError = e;
      LoggerService.error(
        '$prefix falha ao carregar .env primario: $e',
        e,
        s,
      );
    }

    final missingAfterPrimary = _missingRequiredKeys();

    final shouldAttemptFallback =
        loadPlan?.source == EnvironmentSource.externalMachineFile &&
        (!dotenv.isInitialized || missingAfterPrimary.isNotEmpty);
    var fallbackAttempted = false;

    if (shouldAttemptFallback) {
      fallbackAttempted = true;
      LoggerService.error(
        '$prefix arquivo externo carregado mas chaves obrigatorias '
        'ausentes: $missingAfterPrimary. Tentando fallback para asset '
        'bundled (preservando chaves existentes).',
      );
      try {
        await _overlayBundledAsset(
          missingKeys: missingAfterPrimary,
          leakedSecretKeys: leakedSecretKeys,
          logPrefix: prefix,
        );
        LoggerService.info(
          '$prefix fallback para asset bundled aplicado '
          '(chaves agora=${dotenv.env.length})',
        );
      } on Object catch (e, s) {
        primaryError ??= e;
        LoggerService.error(
          '$prefix fallback para asset bundled falhou: $e',
          e,
          s,
        );
      }
    }

    return _buildOutcome(
      source: loadPlan?.source ?? EnvironmentSource.bundledAsset,
      sourceDescription: loadPlan?.description ?? bundledAssetFileName,
      attemptedFallback: fallbackAttempted,
      loadError: primaryError,
      leakedBundledSecretKeys: leakedSecretKeys,
    );
  }

  /// Apaga em `dotenv.env` valores não vazios de chaves classificadas
  /// como [forbiddenInBundledAssetKeys] quando essas chaves vieram de
  /// uma fonte "não confiável" (asset bundled). Registra o incidente em
  /// [leakedKeys] para inspeção no [EnvironmentLoadOutcome].
  static void _scrubLeakedSecretsFromCurrentEnv({
    required Set<String> leakedKeys,
    required String source,
    required String logPrefix,
  }) {
    for (final key in forbiddenInBundledAssetKeys) {
      final raw = dotenv.env[key];
      if (raw == null || raw.trim().isEmpty) continue;
      leakedKeys.add(key);
      dotenv.env[key] = '';
      LoggerService.error(
        '$logPrefix SEGREDO VAZADO em $source: chave "$key" tinha valor '
        'nao-vazio e foi APAGADA em runtime. Mova o valor real para '
        r'`C:\ProgramData\BackupDatabase\config\.env` e mantenha o '
        'asset bundled limpo.',
      );
    }
  }

  /// Carrega o asset bundled diretamente via `dotenv.load()` quando ele é
  /// a origem primária (modo dev / sem arquivo externo).
  static Future<void> _loadBundledAsset() async {
    final reader = bundledAssetReader;
    if (reader != null) {
      final assetText = await reader(bundledAssetFileName);
      dotenv.loadFromString(envString: assetText);
      return;
    }
    await dotenv.load();
  }

  /// Lê o asset bundled e mescla apenas as chaves ausentes/vazias —
  /// preserva overrides intencionais do arquivo externo (ex.: usuário
  /// limpou propositalmente `BACKUP_DATABASE_LICENSE_PRIVATE_KEY=` em
  /// produção, ou deixou `FTP_IT_*` em branco; não queremos
  /// re-popular essas chaves do bundled asset).
  ///
  /// **Segurança**: chaves listadas em [forbiddenInBundledAssetKeys] são
  /// **ignoradas** mesmo que apareçam no asset com valor — vão para a
  /// lista [leakedSecretKeys] e o operador é alertado via log `error`.
  static Future<void> _overlayBundledAsset({
    required Set<String> missingKeys,
    required Set<String> leakedSecretKeys,
    required String logPrefix,
  }) async {
    final reader = bundledAssetReader;
    final assetText = reader != null
        ? await reader(bundledAssetFileName)
        : await _safeRootBundleLoad(bundledAssetFileName);
    if (assetText == null || assetText.isEmpty) {
      return;
    }

    for (final line in assetText.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex <= 0) continue;
      final key = trimmed.substring(0, eqIndex).trim();
      final rawValue = trimmed.substring(eqIndex + 1);
      final value = _stripInlineComment(rawValue).trim();
      if (value.isEmpty) continue;
      if (forbiddenInBundledAssetKeys.contains(key)) {
        // Chave forbidden encontrada com valor no asset — refuse e alerta.
        leakedSecretKeys.add(key);
        LoggerService.error(
          '$logPrefix SEGREDO VAZADO em bundled asset: chave "$key" '
          'tinha valor nao-vazio. IGNORANDO no overlay. Mova o valor '
          r'real para `C:\ProgramData\BackupDatabase\config\.env`.',
        );
        continue;
      }
      if (!missingKeys.contains(key)) continue;
      final existing = dotenv.env[key];
      if (existing != null && existing.trim().isNotEmpty) continue;
      dotenv.env[key] = value;
    }
  }

  static String _stripInlineComment(String raw) {
    // Conservador: só corta `#` precedido por whitespace para não
    // quebrar URLs / valores com `#` literal.
    final match = RegExp(r'\s#').firstMatch(raw);
    if (match == null) return raw;
    return raw.substring(0, match.start);
  }

  static Future<String?> _safeRootBundleLoad(String assetKey) async {
    // Sem `bundledAssetReader` injetado, não podemos importar
    // `package:flutter/services.dart` aqui sem acoplar o `EnvironmentLoader`
    // ao binding de widgets (quebra testes Dart puros). O `AppBootstrap`
    // deve registrar `EnvironmentLoader.bundledAssetReader` no startup
    // (`rootBundle.loadString(...)`). Sem reader, devolvemos `null` —
    // o fallback fica no-op em testes que não fazem setup.
    return null;
  }

  static Set<String> _missingRequiredKeys() {
    if (!dotenv.isInitialized) {
      return Set<String>.unmodifiable(requiredKeys);
    }
    return requiredKeys.where((key) {
      final value = dotenv.env[key];
      return value == null || value.trim().isEmpty;
    }).toSet();
  }

  static EnvironmentLoadOutcome _buildOutcome({
    required EnvironmentSource source,
    required String sourceDescription,
    required bool attemptedFallback,
    Object? loadError,
    Set<String> leakedBundledSecretKeys = const <String>{},
  }) {
    final missing = _missingRequiredKeys();
    return EnvironmentLoadOutcome(
      source: source,
      sourceDescription: sourceDescription,
      loadedKeyCount: dotenv.isInitialized ? dotenv.env.length : 0,
      missingRequiredKeys: Set<String>.unmodifiable(missing),
      attemptedFallback: attemptedFallback,
      dotenvInitialized: dotenv.isInitialized,
      loadError: loadError,
      leakedBundledSecretKeys: Set<String>.unmodifiable(
        leakedBundledSecretKeys,
      ),
    );
  }

  /// Reseta o estado mantido pelo loader. Apenas para testes.
  static void resetForTesting() {
    bundledAssetReader = null;
  }
}
