abstract class ISingleInstanceIpcClient {
  Future<bool> notifyExistingInstance();

  Future<bool> checkServerRunning();

  Future<String?> getExistingInstanceUser();
}
