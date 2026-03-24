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
}
