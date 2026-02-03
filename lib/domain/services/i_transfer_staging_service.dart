abstract class ITransferStagingService {
  Future<String?> copyToStaging(String backupPath, String scheduleId);
}
