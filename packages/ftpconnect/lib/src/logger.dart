class Logger {
  Logger({this.isEnabled = false});

  final bool isEnabled;
  final Set<String> _credentials = {};

  void log(String pMessage) {
    final command =
        RegExp(r'^>\s*(?:PASS|ACCT|ADAT)\s+([\s\S]*)$', caseSensitive: false)
            .firstMatch(pMessage);
    if (command != null) {
      final credential = command[1]!;
      if (credential.isNotEmpty) _credentials.add(credential);
      pMessage = '> [credential command omitted]';
    }
    for (final credential in _credentials) {
      pMessage = pMessage.replaceAll(credential, '[redacted]');
    }
    if (isEnabled) _printLog(pMessage);
  }

  void _printLog(String pMessage) {
    print('[${DateTime.now()}] $pMessage');
  }
}
