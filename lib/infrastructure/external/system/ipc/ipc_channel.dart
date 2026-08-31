abstract class IIpcChannel {
  Future<String?> readLine({required Duration timeout});

  Future<void> writeLine(String line);

  Future<void> close();
}

abstract class IIpcTransport {
  Future<bool> startServer({
    required Future<void> Function(IIpcChannel channel) onConnection,
  });

  Future<void> stopServer();

  bool get isServerRunning;

  Future<IIpcChannel?> connect({required Duration timeout});
}
