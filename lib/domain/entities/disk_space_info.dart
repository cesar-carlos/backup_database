class DiskSpaceInfo {
  const DiskSpaceInfo({
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
    required this.usedPercentage,
  });
  final int totalBytes;
  final int freeBytes;
  final int usedBytes;
  final double usedPercentage;

  bool hasEnoughSpace(int requiredBytes) => freeBytes >= requiredBytes;
}
