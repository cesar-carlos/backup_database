import 'dart:async';

/// A timeout does not cancel a native connect running in another isolate.
/// Transfer ownership only if the caller is still waiting; otherwise close it.
Future<int?> awaitPipeConnection({
  required Future<int?> connection,
  required Duration timeout,
  required void Function(int) close,
}) async {
  var expired = false;
  final owned = connection.then((handle) {
    if (expired && handle != null) {
      close(handle);
      return null;
    }
    return handle;
  });
  return owned.timeout(
    timeout,
    onTimeout: () {
      expired = true;
      throw TimeoutException('Named pipe connection timed out', timeout);
    },
  );
}
