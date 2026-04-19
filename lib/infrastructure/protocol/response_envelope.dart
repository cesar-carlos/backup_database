import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/status_codes.dart';

/// Helper que adiciona o envelope REST-like (`success`/`statusCode`)
/// a um payload de sucesso. Implementa F0.5 do plano.
///
/// Estrategia ADITIVA top-level (nao envelope completo com `data`):
/// servidor `v2` adiciona dois campos top-level (`success: true`,
/// `statusCode: 200`) sem mover o payload existente para dentro de
/// `data`. Cliente `v1` continua lendo campos diretamente; cliente
/// `v2+` pode usar `success`/`statusCode` como gate sincrono. Wire
/// format compativel sem precisar bump de `protocolVersion`.
///
/// `data` envelope completo fica reservado para `v2`/`v3` quando
/// houver bump real do protocolo (ver ADR-003); a estrategia atual
/// permite migrar 100% dos handlers sem quebrar peers ja em campo.
///
/// [statusCode] default `200` (sucesso sincrono); use `202` quando
/// resposta indica aceite assincrono (ex.: `executeBackup` futuro
/// que vai retornar `runId` sem bloquear).
Map<String, dynamic> wrapSuccessResponse(
  Map<String, dynamic> data, {
  int statusCode = StatusCodes.ok,
}) {
  return <String, dynamic>{
    'success': true,
    'statusCode': statusCode,
    ...data,
  };
}

/// Le `success` do payload da mensagem. Retorna `null` quando o
/// servidor nao envia o campo (servidor `v1` legado). Cliente pode
/// usar `getSuccessFromMessage(msg) ?? !isErrorMessage(msg)` como
/// fallback conservador — assume sucesso se a mensagem nao e do tipo
/// `error`.
bool? getSuccessFromMessage(Message message) {
  final raw = message.payload['success'];
  return raw is bool ? raw : null;
}
