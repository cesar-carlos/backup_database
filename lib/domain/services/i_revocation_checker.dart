abstract interface class IRevocationChecker {
  Future<bool> isRevoked(String deviceKey);
}
