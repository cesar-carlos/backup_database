import 'dart:async';

import 'package:backup_database/infrastructure/protocol/message.dart';

/// Registry de idempotencia para comandos mutaveis (F2.5/F2.14).
///
/// **Problema**: cliente pode reenviar `startBackup`/`cancelBackup`/
/// `createSchedule` por reconexao, retry agressivo ou bug. Sem
/// deduplicacao, cada retransmissao dispara nova execucao real.
///
/// **Solucao**: cliente envia `idempotencyKey` (string opaca) em cada
/// request mutavel. Servidor consulta o registry: se a chave ja foi
/// vista dentro da janela [_ttl], devolve a MESMA resposta original
/// armazenada (cached). Se nao, processa a request, armazena a
/// resposta e retorna.
///
/// **Garantias**:
/// - Mesma chave dentro da janela -> mesma resposta (semantica
///   "exactly-once" do ponto de vista do cliente).
/// - Chaves diferentes -> processamento independente.
/// - Janela TTL evita memoria infinita; chaves antigas sao GC.
/// - Thread-safe via Future-based completion (gravacao atomica
///   seguida de leitura concorrente sem race).
///
/// **Limitacoes conhecidas (v1)**:
/// - In-memory: reinicio do servidor perde o registry. Cliente que
///   tentar retransmitir apos restart vai disparar nova execucao.
///   Persistencia (F2.16) entra em PR-3.
/// - Cliente e responsavel por escolher chaves estaveis (`scheduleId`
///   + epoch ms truncado por minuto, ou UUID v4 cacheado por
///   `requestId` no cliente). Chave nao-estavel anula a defesa.
///
/// **Uso**:
/// ```dart
/// final registry = IdempotencyRegistry();
/// final result = await registry.runIdempotent<Message>(
///   key: payload['idempotencyKey'] as String?,
///   compute: () async => createSuccessResponse(...),
/// );
/// // result e a resposta a ser enviada (cached ou recem-computada).
/// ```
class IdempotencyRegistry {
  IdempotencyRegistry({
    Duration ttl = const Duration(minutes: 5),
    DateTime Function()? clock,
  })  : _ttl = ttl,
        _clock = clock ?? DateTime.now;

  final Duration _ttl;
  final DateTime Function() _clock;
  final Map<String, _CachedEntry> _entries = <String, _CachedEntry>{};

  /// Tamanho atual do registry — exposto para testes/observabilidade.
  int get size {
    _purgeExpired();
    return _entries.length;
  }

  /// Executa [compute] respeitando idempotencia. Quando [key] e `null`
  /// ou vazio, [compute] e SEMPRE executado (idempotencia opt-in;
  /// cliente que nao envia chave aceita o comportamento legado).
  ///
  /// Quando [key] esta presente:
  /// - 1a chamada: [compute] roda, resposta e cacheada e retornada.
  /// - Chamadas subsequentes dentro do TTL: retornam o cache (sem
  ///   re-executar [compute]).
  /// - Apos TTL: cache e descartado e [compute] roda novamente
  ///   (request "nova" do ponto de vista da janela).
  ///
  /// Concorrencia: requests simultaneos com a mesma chave aguardam o
  /// mesmo Future — garante que [compute] roda APENAS uma vez mesmo
  /// sob race (defesa contra cliente que duplica request entre dois
  /// clients distintos da mesma sessao).
  Future<T> runIdempotent<T>({
    required String? key,
    required Future<T> Function() compute,
  }) async {
    if (key == null || key.isEmpty) {
      // Idempotencia opt-in. Sem chave, comportamento legado.
      return compute();
    }

    _purgeExpired();
    final existing = _entries[key];
    if (existing != null) {
      // Cast seguro: registry e por-tipo de comando; se chave foi
      // usada com tipo diferente, e bug de chamador (chave duplicada
      // entre comandos distintos). Erro explicito ajuda a detectar.
      final cached = existing.completer.future;
      return cached.then((value) {
        if (value is T) return value;
        throw StateError(
          'IdempotencyRegistry: chave "$key" ja foi usada com tipo '
          'diferente (${value.runtimeType} vs $T). Cliente deve usar '
          'chaves distintas para comandos distintos.',
        );
      });
    }

    final completer = Completer<dynamic>();
    _entries[key] = _CachedEntry(
      completer: completer,
      expiresAt: _clock().add(_ttl),
    );
    try {
      final value = await compute();
      completer.complete(value);
      return value;
    } on Object catch (e, st) {
      // Falha NAO e cacheada — request quebrou e cliente deve poder
      // tentar novamente sem ter a falha "fixada" pelo registry.
      // Remove entry e propaga erro para waiters concorrentes.
      _entries.remove(key);
      completer.completeError(e, st);
      // Silencia uncaught-error caso nao haja waiters concorrentes
      // (cenario comum: 1a request falha sem que haja segunda em
      // andamento). Sem isso o Future do completer torna-se uncaught
      // assincrono porque ninguem await nele apos o rethrow abaixo.
      unawaited(completer.future.catchError((Object _) => null as dynamic));
      rethrow;
    }
  }

  /// Limpa entries expirados. Chamado on-demand em [size] e
  /// [runIdempotent]; nao precisa Timer dedicado em v1 (volume
  /// esperado e baixo, < 100 entries simultaneos).
  void _purgeExpired() {
    final now = _clock();
    _entries.removeWhere((_, entry) => entry.expiresAt.isBefore(now));
  }

  /// Limpa o registry. Util em testes e em shutdown.
  void clear() => _entries.clear();
}

class _CachedEntry {
  _CachedEntry({required this.completer, required this.expiresAt});

  final Completer<dynamic> completer;
  final DateTime expiresAt;
}

/// Le `idempotencyKey` de uma mensagem. Retorna `null` quando ausente
/// ou nao-string. Cliente que nao envia chave opta por comportamento
/// legado (idempotencia opt-in).
String? getIdempotencyKey(Message message) {
  final raw = message.payload['idempotencyKey'];
  if (raw is! String) return null;
  if (raw.isEmpty) return null;
  return raw;
}
