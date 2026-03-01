class Logger {
  Logger({this.isEnabled = false});

  final bool isEnabled;

  void log(String pMessage) {
    if (isEnabled) _printLog(pMessage);
  }

  void _printLog(String pMessage) {
    print('[${DateTime.now()}] $pMessage');
  }
}
