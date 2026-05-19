import 'package:backup_database/application/providers/backup_progress_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BackupProgressProvider provider;

  setUp(() {
    provider = BackupProgressProvider();
  });

  group('BackupProgressProvider.tryStartBackup', () {
    test('should reserve slot when no backup is running', () {
      final reserved = provider.tryStartBackup('Schedule A');

      expect(reserved, isTrue);
      expect(provider.isRunning, isTrue);
      expect(provider.currentBackupName, 'Schedule A');
      expect(provider.currentProgress?.step, BackupStep.initializing);
    });

    test('should reject second start while backup is running', () {
      expect(provider.tryStartBackup('First'), isTrue);
      expect(provider.tryStartBackup('Second'), isFalse);
      expect(provider.currentBackupName, 'First');
    });

    test('should allow generic message when schedule name is null', () {
      provider.tryStartBackup();

      expect(provider.currentProgress?.message, 'Iniciando backup...');
    });
  });

  group('BackupProgressProvider.updateProgress', () {
    test('should map known step strings from remote protocol', () {
      provider.tryStartBackup('Remote');

      provider.updateProgress(
        step: 'Executando backup',
        message: '50%',
        progress: 0.5,
      );

      expect(provider.currentProgress?.step, BackupStep.executingBackup);
      expect(provider.currentProgress?.progress, 0.5);
    });

    test('should map upload-prefixed steps to uploading', () {
      provider.tryStartBackup('Remote');

      provider.updateProgress(
        step: 'Enviando para Google Drive',
        message: 'upload',
      );

      expect(provider.currentProgress?.step, BackupStep.uploading);
    });

    test('should ignore unknown step when not running', () {
      provider.updateProgress(
        step: 'Executando backup',
        message: 'ignored',
      );

      expect(provider.currentProgress, isNull);
    });
  });

  group('BackupProgressProvider lifecycle', () {
    test('should clear running state on completeBackup', () {
      provider.tryStartBackup('Done');
      provider.completeBackup(backupPath: r'C:\out\file.bak');

      expect(provider.isRunning, isFalse);
      expect(provider.currentBackupName, isNull);
      expect(provider.currentProgress?.step, BackupStep.completed);
      expect(provider.currentProgress?.backupPath, r'C:\out\file.bak');
    });

    test('should clear running state on failBackup', () {
      provider.tryStartBackup('Fail');
      provider.failBackup('disk full');

      expect(provider.isRunning, isFalse);
      expect(provider.currentProgress?.step, BackupStep.error);
      expect(provider.currentProgress?.error, 'disk full');
    });

    test('should reset all state', () {
      provider.tryStartBackup('X');
      provider.reset();

      expect(provider.isRunning, isFalse);
      expect(provider.currentProgress, isNull);
      expect(provider.currentBackupName, isNull);
    });
  });

  group('BackupProgressProvider.cancel and history', () {
    test('should set cancelRequested when markCancelRequested', () {
      provider.tryStartBackup('Cancel me');
      provider.markCancelRequested();

      expect(provider.currentProgress?.cancelRequested, isTrue);
    });

    test('should not mark cancel when not running', () {
      provider.markCancelRequested();
      expect(provider.currentProgress, isNull);
    });

    test('should attach historyId while running', () {
      provider.tryStartBackup('Hist');
      provider.setCurrentHistoryId('hist-42');

      expect(provider.currentProgress?.historyId, 'hist-42');
      expect(provider.currentSnapshot?.historyId, 'hist-42');
    });

    test('should ignore setCurrentHistoryId when not running', () {
      provider.setCurrentHistoryId('hist-99');
      expect(provider.currentProgress, isNull);
    });
  });
}
