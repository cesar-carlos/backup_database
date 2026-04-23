/// Origem da execução de backup no servidor (ver ADR-001).
///
/// - [local]: timer de agendamento (`_checkTimer`) ou "Executar agora" na UI
///   do servidor. Upload para destinos finais **habilitado** conforme o
///   agendamento.
/// - [remoteCommand]: comando vindo do cliente (socket). Modo *server-first*:
///   o servidor **não** envia o artefato para destinos finais configurados no
///   próprio host; publica em staging para o cliente baixar.
enum ExecutionOrigin {
  local,
  remoteCommand,
}
