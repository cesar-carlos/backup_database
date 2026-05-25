class SingleInstanceScheduledDelegationResult {
  const SingleInstanceScheduledDelegationResult({
    required this.exitCode,
    this.message,
  });

  final int exitCode;
  final String? message;
}

class SingleInstanceOwnerInfo {
  const SingleInstanceOwnerInfo({
    required this.role,
    required this.canRunSchedule,
  });

  final String role;
  final bool canRunSchedule;
}

abstract class ISingleInstanceIpcClient {
  Future<bool> notifyExistingInstance();

  Future<bool> checkServerRunning();

  Future<String?> getExistingInstanceUser();

  Future<String?> getExistingInstanceRole();

  Future<SingleInstanceOwnerInfo?> getExistingInstanceInfo();

  Future<SingleInstanceScheduledDelegationResult?> delegateScheduledExecution(
    String scheduleId,
  );
}
