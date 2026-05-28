/// Snapshot do estado de elevação do processo no SO.
///
/// `null` para `uacEnabled` e `processIsElevated` indica que a detecção
/// não foi confiável (sem permissão de leitura do registry, falha em
/// `OpenProcessToken`, etc.). Callers devem tratar `null` como "não
/// sabemos" e seguir uma política conservadora (no caso do auto-update:
/// **não** bloquear no modo silencioso só por suspeita — UAC ainda
/// vai aparecer e o operador decide).
class ElevationSnapshot {
  const ElevationSnapshot({
    required this.uacEnabled,
    required this.processIsElevated,
    this.diagnostic,
  });

  /// `true` quando o Windows está com **User Account Control** ativo
  /// (registry `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\EnableLUA`
  /// = 1). `null` quando a leitura falhou.
  final bool? uacEnabled;

  /// `true` quando o processo atual tem token elevado (admin). `null`
  /// quando `OpenProcessToken`/`GetTokenInformation` falharam.
  final bool? processIsElevated;

  /// Texto opcional descrevendo o caminho de detecção (útil em log e
  /// diagnostico). Não exibir cru ao usuário final.
  final String? diagnostic;

  /// `true` apenas quando o auto-update silencioso vai **inevitavelmente**
  /// disparar prompt UAC visível ao usuário interativo:
  ///   - UAC ativo no sistema, **e**
  ///   - o processo atual não está elevado.
  ///
  /// Defesa conservadora: se qualquer um dos dois bits for `null`
  /// (detecção não confiável), assume `false` — preferimos correr o
  /// risco do prompt UAC silencioso do que bloquear updates legítimos
  /// em todas as máquinas onde a detecção é frágil.
  bool get wouldTriggerUacPrompt {
    final uac = uacEnabled;
    final elevated = processIsElevated;
    if (uac == null || elevated == null) return false;
    return uac && !elevated;
  }
}

/// Probe injetável que devolve um [ElevationSnapshot] do SO atual.
///
/// §audit-2026-05-28 wave 4: o auto-update silencioso assume que o
/// processo consegue lançar o instalador sem disparar prompt UAC.
/// Em máquinas com UAC ativo + UI rodando como usuário comum, esse
/// pressuposto falha — o usuário vê um prompt no meio do trabalho,
/// muitas vezes nega por reflexo, e o update marca como falha
/// "spawn aborted". Esta interface dá um ponto único para detectar
/// e gatear esse cenário.
abstract class IElevationProbe {
  Future<ElevationSnapshot> probe();
}
