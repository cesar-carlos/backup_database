import 'dart:async';

class Utils {
  Utils._();

  static int parsePort(String response, bool isIPV6) {
    return isIPV6 ? parsePortEPSV(response) : parsePortPASV(response);
  }

  static int parsePortEPSV(String sResponse) {
    final iParOpen = sResponse.indexOf('(');
    final iParClose = sResponse.indexOf(')');

    if (iParClose > -1 && iParOpen > -1) {
      sResponse = sResponse.substring(iParOpen + 4, iParClose - 1);
    }
    return int.parse(sResponse);
  }

  static int parsePortPASV(String sResponse) {
    final iParOpen = sResponse.indexOf('(');
    final iParClose = sResponse.indexOf(')');

    final sParameters = sResponse.substring(iParOpen + 1, iParClose);
    final lstParameters = sParameters.split(',');

    final iPort1 = int.parse(lstParameters[lstParameters.length - 2]);
    final iPort2 = int.parse(lstParameters[lstParameters.length - 1]);

    return (iPort1 * 256) + iPort2;
  }

  static Future<bool> retryAction(
    FutureOr<bool> Function() action,
    int retryCount,
  ) async {
    var lAttempts = 1;
    var result = true;
    await Future.doWhile(() async {
      try {
        result = await action();
        return false;
      } catch (e) {
        if (lAttempts++ >= retryCount) {
          rethrow;
        }
      }
      return true;
    });
    return result;
  }
}
