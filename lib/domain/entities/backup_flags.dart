class BackupFlags {
  const BackupFlags({
    required this.compression,
    required this.verifyPolicy,
    required this.stripingCount,
    required this.withChecksum,
    required this.stopOnError,
  });

  final bool compression;
  final String verifyPolicy;
  final int stripingCount;
  final bool withChecksum;
  final bool stopOnError;
}
