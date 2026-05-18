/// Limites de taxa por conexao de cliente (M5.1 do plano remoto).
class SocketRateLimit {
  SocketRateLimit._();

  static const int maxRequestsPerSecondPerClient = 20;
  static const int maxMutatingCommandsPerMinutePerClient = 30;
}
