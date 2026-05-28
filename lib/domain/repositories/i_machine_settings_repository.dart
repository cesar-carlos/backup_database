abstract class IMachineSettingsRepository {
  Future<bool> getStartWithWindows();

  Future<void> setStartWithWindows(bool value);

  Future<bool> getStartMinimized();

  Future<void> setStartMinimized(bool value);

  Future<String?> getCustomTempDownloadsPath();

  Future<void> setCustomTempDownloadsPath(String? path);

  Future<String?> getReceivedBackupsDefaultPath();

  Future<void> setReceivedBackupsDefaultPath(String? path);

  Future<String?> getScheduleTransferDestinationsJson();

  Future<void> setScheduleTransferDestinationsJson(String? json);

  /// §audit-2026-05-28 wave 3 (P2): snapshot mínimo de execução remota
  /// pendente para retomar depois de um restart do processo (auto-update,
  /// crash, logoff). Armazena JSON `{runId, scheduleId, startedAt}`.
  /// `null` quando não há run pendente — campo é limpo ao concluir,
  /// falhar ou cancelar a execução remota.
  Future<String?> getPendingRemoteRunSnapshotJson();

  Future<void> setPendingRemoteRunSnapshotJson(String? json);
}
