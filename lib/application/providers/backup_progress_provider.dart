import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

enum BackupStep {
  initializing,
  executingBackup,
  compressing,
  uploading,
  completed,
  error,
}

class BackupProgress {
  const BackupProgress({
    required this.step,
    required this.message,
    this.progress,
    this.error,
    this.startedAt,
    this.elapsed,
  });
  final BackupStep step;
  final String message;
  final double? progress;
  final String? error;
  final DateTime? startedAt;
  final Duration? elapsed;

  BackupProgress copyWith({
    BackupStep? step,
    String? message,
    double? progress,
    String? error,
    DateTime? startedAt,
    Duration? elapsed,
  }) {
    return BackupProgress(
      step: step ?? this.step,
      message: message ?? this.message,
      progress: progress ?? this.progress,
      error: error ?? this.error,
      startedAt: startedAt ?? this.startedAt,
      elapsed: elapsed ?? this.elapsed,
    );
  }
}

class BackupProgressProvider extends ChangeNotifier {
  BackupProgress? _currentProgress;
  bool _isRunning = false;

  BackupProgress? get currentProgress => _currentProgress;
  bool get isRunning => _isRunning;

  void startBackup(String scheduleName) {
    _isRunning = true;
    _currentProgress = BackupProgress(
      step: BackupStep.initializing,
      message: 'Iniciando backup: $scheduleName',
      startedAt: DateTime.now(),
      progress: 0,
    );
    notifyListeners();
  }

  void updateProgress({
    required BackupStep step,
    required String message,
    double? progress,
  }) {
    if (!_isRunning) return;

    final elapsed = _currentProgress?.startedAt != null
        ? DateTime.now().difference(_currentProgress!.startedAt!)
        : null;

    _currentProgress =
        _currentProgress?.copyWith(
          step: step,
          message: message,
          progress: progress,
          elapsed: elapsed,
        ) ??
        BackupProgress(
          step: step,
          message: message,
          progress: progress,
          startedAt: DateTime.now(),
        );
    notifyListeners();
  }

  void completeBackup({String? message}) {
    _isRunning = false;
    final elapsed = _currentProgress?.startedAt != null
        ? DateTime.now().difference(_currentProgress!.startedAt!)
        : null;

    _currentProgress = _currentProgress?.copyWith(
      step: BackupStep.completed,
      message: message ?? 'Backup concluído com sucesso!',
      progress: 1,
      elapsed: elapsed,
    );
    notifyListeners();
  }

  void failBackup(String error) {
    _isRunning = false;
    final elapsed = _currentProgress?.startedAt != null
        ? DateTime.now().difference(_currentProgress!.startedAt!)
        : null;

    _currentProgress = _currentProgress?.copyWith(
      step: BackupStep.error,
      message: 'Erro no backup',
      error: error,
      elapsed: elapsed,
    );
    notifyListeners();
  }

  void reset() {
    _isRunning = false;
    _currentProgress = null;
    notifyListeners();
  }

  static BackupProgressProvider of(BuildContext context) {
    return Provider.of<BackupProgressProvider>(context, listen: false);
  }
}
