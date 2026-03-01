class FTPConnectException implements Exception {
  FTPConnectException(this.message, [this.response]);

  final String message;
  final String? response;

  @override
  String toString() {
    return 'FTPConnectException: $message (Response: $response)';
  }
}
