import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';

/// Maquina de estados oficial de uma execucao remota (PR-3, F2.13).
///
/// Estados sao [ExecutionState] (compartilhado com o protocolo).
/// Transicoes proibidas lancam [InvalidStateTransitionException] —
/// errar uma transicao e bug logico, nao excecao operacional.
///
/// Tabela oficial de transicoes (todas no servidor):
///
/// ```text
///                  +-----------+
///                  |  queued   |---> cancelled  (cancelQueuedBackup)
///                  +-----------+
///                       |
///                       v (drain do queue ou direto via startBackup)
///                  +-----------+
///                  |  running  |---> completed  (sucesso)
///                  +-----------+ \-> failed     (erro)
///                       |       \-> cancelled  (cancelBackup)
///                       v
///                  +-----------+
///                  | (terminal)|  completed | failed | cancelled
///                  +-----------+
/// ```
///
/// **Estados terminais**: `completed`, `failed`, `cancelled`. Nenhuma
/// transicao saindo deles e permitida (qualquer tentativa = bug).
///
/// **Estados nao-cobertos pela maquina**:
/// - `notFound`: meta-estado de "execucao nao existe" — nao e uma
///   transicao real, e a resposta natural quando o cliente consulta
///   um runId desconhecido. NAO entra na tabela.
/// - `unknown`: defesa para servidor `v1` ou parsing defensivo;
///   tambem nao participa de transicoes.
class ExecutionStateMachine {
  ExecutionStateMachine._();

  /// Tabela imutavel de transicoes permitidas.
  ///
  /// Cada entry: estado origem -> Set de estados destino aceitos.
  static final Map<ExecutionState, Set<ExecutionState>> _transitions = {
    ExecutionState.queued: {
      ExecutionState.running,
      ExecutionState.cancelled,
    },
    ExecutionState.running: {
      ExecutionState.completed,
      ExecutionState.failed,
      ExecutionState.cancelled,
    },
    // Estados terminais: sem transicoes saindo.
    ExecutionState.completed: <ExecutionState>{},
    ExecutionState.failed: <ExecutionState>{},
    ExecutionState.cancelled: <ExecutionState>{},
    // notFound e unknown intencionalmente nao listados — qualquer
    // transicao envolvendo eles e bug do chamador.
  };

  /// Conjunto de estados terminais (sem transicoes de saida).
  static final Set<ExecutionState> terminalStates = <ExecutionState>{
    ExecutionState.completed,
    ExecutionState.failed,
    ExecutionState.cancelled,
  };

  /// Verifica se [from] -> [to] e uma transicao permitida pela tabela.
  /// Retorna `false` para qualquer transicao envolvendo `notFound` ou
  /// `unknown` (estados nao-modelados na maquina).
  static bool canTransition(ExecutionState from, ExecutionState to) {
    final allowed = _transitions[from];
    if (allowed == null) return false;
    return allowed.contains(to);
  }

  /// Valida uma transicao. Lanca [InvalidStateTransitionException] se
  /// nao for permitida. Use no servidor antes de publicar mudanca de
  /// estado para garantir que codigo upstream NAO criou estado
  /// inconsistente (ex.: tentou mover `completed -> running`).
  static void enforceTransition(ExecutionState from, ExecutionState to) {
    if (!canTransition(from, to)) {
      throw InvalidStateTransitionException(from, to);
    }
  }

  /// `true` se o estado nao admite mais transicoes (cliente pode
  /// limpar timers de polling, fechar streams etc.).
  static bool isTerminal(ExecutionState state) => terminalStates.contains(state);

  /// Lista de transicoes permitidas a partir de [from]. Util para UIs
  /// que mostram "acoes disponiveis" para um runId (ex.: botao Cancelar
  /// so aparece se `running ∈ allowedFrom(currentState)`).
  static Set<ExecutionState> allowedFrom(ExecutionState from) =>
      Set<ExecutionState>.unmodifiable(_transitions[from] ?? const {});
}

/// Lancada quando o codigo do servidor tenta uma transicao proibida
/// pela [ExecutionStateMachine]. Indica bug — nao deve ocorrer em
/// fluxo normal. Mensagem inclui both estados para diagnostico.
class InvalidStateTransitionException implements Exception {
  const InvalidStateTransitionException(this.from, this.to);

  final ExecutionState from;
  final ExecutionState to;

  @override
  String toString() =>
      'InvalidStateTransitionException: ${from.name} -> ${to.name} '
      'nao e uma transicao permitida pela ExecutionStateMachine';
}
