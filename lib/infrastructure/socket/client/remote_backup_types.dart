class RemoteBackupCancelledException implements Exception {
  RemoteBackupCancelledException({
    required this.cancelledBy,
    this.reason,
    this.occurredAt,
  });

  final String cancelledBy;
  final String? reason;
  final DateTime? occurredAt;

  @override
  String toString() {
    final reasonPart = reason != null ? ', reason=$reason' : '';
    final whenPart = occurredAt != null
        ? ', occurredAt=${occurredAt!.toIso8601String()}'
        : '';
    return 'RemoteBackupCancelledException(cancelledBy=$cancelledBy$reasonPart$whenPart)';
  }
}

typedef BackupProgressCallback = void Function(
  String step,
  String message,
  double progress,
);
