import 'dart:convert';

import 'package:backup_database/application/services/auto_update_service.dart'
    show AppUpdateDecision, AppcastRelease;
import 'package:pub_semver/pub_semver.dart';

/// Engine de decisão que escolhe a próxima `AppcastRelease` aplicável
/// para a versão local instalada.
///
/// Extraído do `auto_update_service.dart` para isolar a lógica de
/// decisão (`evaluateRelease`) e do `passesRollout` (FNV-1a-baseado
/// para staged rollout determinístico por máquina) — ambos são funções
/// puras, testáveis sem qualquer side-effect.
///
/// O método estático original `AutoUpdateService.evaluateRelease` foi
/// mantido como façade `@visibleForTesting` que delega para
/// [AppUpdateDecisionEngine.evaluate], preservando os testes existentes.
abstract final class AppUpdateDecisionEngine {
  /// Avalia a lista de `releases` (já ordenadas decrescente por versão)
  /// contra a `currentVersion` instalada e devolve a primeira que:
  /// - é estritamente mais nova,
  /// - cumpre `minSupportedAppVersion` se declarado, e
  /// - passa no critério de staged rollout (ver [passesRollout]).
  ///
  /// Quando nenhuma release qualifica, devolve `AppUpdateDecision`
  /// com `latestRelease == null` (cliente já está atualizado).
  static AppUpdateDecision evaluate({
    required List<AppcastRelease> releases,
    required Version currentVersion,
    String? machineId,
  }) {
    for (final release in releases) {
      if (release.version <= currentVersion) continue;
      if (release.minSupportedAppVersion != null &&
          currentVersion < release.minSupportedAppVersion!) {
        continue;
      }
      if (!passesRollout(release, machineId)) continue;

      return AppUpdateDecision(
        currentVersion: currentVersion,
        latestRelease: release,
      );
    }

    return AppUpdateDecision(
      currentVersion: currentVersion,
      latestRelease: null,
    );
  }

  /// Implementa staged rollout: se `rolloutPercentage` está presente,
  /// considera o cliente "elegível" apenas quando `hash(machineId) %
  /// 100` for menor que a porcentagem. Sem `machineId` confiável,
  /// deixa todos passarem para não bloquear updates por falta de
  /// dado (fail-open).
  ///
  /// `pct == null` ou `>= 100` → todos passam.
  /// `pct <= 0` → ninguém passa.
  /// Caso intermediário → hash determinístico por `(targetVersion:machineId)`.
  static bool passesRollout(AppcastRelease release, String? machineId) {
    final pct = release.rolloutPercentage;
    if (pct == null || pct >= 100) return true;
    if (pct <= 0) return false;

    final id = machineId?.trim();
    if (id == null || id.isEmpty) return true;

    final key = '${release.targetVersion}:$id';
    return _fnv1a32(key) % 100 < pct;
  }

  /// FNV-1a 32-bit. Determinístico e suficiente para distribuição
  /// uniforme em staged rollout — não tem garantia criptográfica e
  /// não deve ser usado para uso security-sensitive.
  static int _fnv1a32(String key) {
    const fnvOffset = 0x811C9DC5;
    const fnvPrime = 0x01000193;
    var hash = fnvOffset;
    for (final unit in utf8.encode(key)) {
      hash ^= unit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash;
  }
}
