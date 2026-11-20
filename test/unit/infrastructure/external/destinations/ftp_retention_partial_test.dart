// Mocktail records invocations through closures.
// ignore_for_file: unnecessary_lambdas
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp/ftp_retention.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:mocktail/mocktail.dart';

class _Client extends Mock implements FTPConnect {}

class _Entry extends Mock implements FTPEntry {}

void main() {
  for (final mode in [
    'fresh',
    'old',
    'unknown',
    'invalid-date',
    'directory-failed',
    'list-failed',
    'delete-failed',
  ]) {
    test(
      'should preserve partials and close retention session: $mode',
      () async {
        final ftp = _Client();
        final item = _Entry();
        final name = mode == 'invalid-date'
            ? 'backup_2025-02-31.run.part'
            : 'backup_2025-01-01.run.part';
        when(() => item.name).thenReturn(name);
        when(() => item.type).thenReturn(FTPEntryType.file);
        when(() => item.modifyTime).thenReturn(
          mode == 'unknown'
              ? null
              : mode == 'fresh'
              ? DateTime(2026, 11, 20)
              : DateTime(2025),
        );
        when(() => ftp.connect()).thenAnswer((_) async => true);
        when(() => ftp.changeDirectory('/backups'))
            .thenAnswer((_) async => mode != 'directory-failed');
        when(() => ftp.listDirectoryContent()).thenAnswer((_) async => [item]);
        if (mode == 'list-failed') {
          when(() => ftp.listDirectoryContent())
              .thenThrow(Exception('connection lost'));
        }
        when(() => ftp.deleteFile(name))
            .thenAnswer((_) async => mode != 'delete-failed');
        final result =
            await FtpRetention(
              clientFactory: (_) => ftp,
              clock: () => DateTime(2026, 11, 20),
            ).cleanOldBackups(
              config: const FtpDestinationConfig(
                host: 'test',
                username: 'u',
                password: 'p',
                remotePath: '/backups',
              ),
            );
        verify(() => ftp.abort()).called(1);
        if (mode == 'directory-failed' || mode == 'list-failed') {
          expect(result.isError(), isTrue);
          verifyNever(() => ftp.deleteFile(any()));
        } else {
          expect(result.getOrNull(), mode == 'old' ? 1 : 0);
          if (mode != 'old' && mode != 'delete-failed') {
            verifyNever(() => ftp.deleteFile(any()));
          }
        }
        if (mode == 'directory-failed') {
          verifyNever(() => ftp.listDirectoryContent());
        }
      },
    );
  }
}
