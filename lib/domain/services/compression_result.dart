class CompressionResult {
  final String compressedPath;
  final int compressedSize;
  final int originalSize;
  final Duration duration;
  final double compressionRatio;
  final bool usedWinRar;

  const CompressionResult({
    required this.compressedPath,
    required this.compressedSize,
    required this.originalSize,
    required this.duration,
    required this.compressionRatio,
    this.usedWinRar = false,
  });
}

