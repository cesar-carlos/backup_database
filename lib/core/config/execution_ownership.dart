/// Fixed for the process lifetime. An administrative UI must never fall back
/// to executing backups when the service stops or its IPC times out.
class ExecutionOwnership {
  ExecutionOwnership._();

  static bool administrativeUi = false;

  static bool suppressAutomaticUi({required bool automaticLaunch}) =>
      administrativeUi && automaticLaunch;

  static bool useAdministrativeUi({
    required bool scheduledLaunch,
    required bool serviceInstalled,
    required bool statusUnknown,
  }) => !scheduledLaunch && (serviceInstalled || statusUnknown);
}
