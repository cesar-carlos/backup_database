enum AppDensity {
  compact(
    spacingMultiplier: 0.75,
    targetSize: 36,
  ),
  comfortable(
    spacingMultiplier: 1,
    targetSize: 44,
  ),
  spacious(
    spacingMultiplier: 1.25,
    targetSize: 52,
  )
  ;

  const AppDensity({
    required this.spacingMultiplier,
    required this.targetSize,
  });

  final double spacingMultiplier;
  final double targetSize;
}
