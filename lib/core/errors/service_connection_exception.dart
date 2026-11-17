/// The transport did not open a channel, so this request was never sent.
/// This says nothing about requests sent on earlier connections.
class ServiceConnectionException implements Exception {
  const ServiceConnectionException({this.reason});

  final String? reason;

  @override
  String toString() =>
      'Não foi possível conectar ao serviço do Windows.'
      '${reason == null ? '' : ' Diagnóstico: $reason'}';
}
