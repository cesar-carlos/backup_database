class SybaseVerifyOutcome {
  const SybaseVerifyOutcome({
    required this.success,
    required this.methodUsed,
    required this.duration,
    this.strictFailureMessage,
  });

  final bool success;
  final String methodUsed;
  final Duration duration;

  /// Quando preenchido, indica que o pipeline deve abortar com este
  /// texto em `BackupFailure` (modo strict).
  final String? strictFailureMessage;
}

class SybaseVerifyToolOutcome {
  const SybaseVerifyToolOutcome({
    required this.success,
    required this.errorMessage,
  });

  final bool success;
  final String errorMessage;
}
