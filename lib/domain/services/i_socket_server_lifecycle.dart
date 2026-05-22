abstract class ISocketServerLifecycle {
  bool get isRunning;
  int get port;
  Future<void> start({int port});
}
