import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/presentation/boot/service_account_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _Process extends Mock implements ProcessService {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(Duration.zero);
  });
  for (final output in ['True', 'False', '']) {
    test('custom WinSW account requires admin token: $output', () async {
      final process = _Process();
      when(
        () => process.run(
          executable: any(named: 'executable'),
          arguments: any(named: 'arguments'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer(
        (_) async => rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: output,
            stderr: '',
            duration: Duration.zero,
          ),
        ),
      );
      final probe = ServiceAccountProbe(
        serviceName: 'BackupDatabaseService',
        processService: process,
      );
      final reason = await probe.silentUpdateBlockReason(
        r'CONTOSO\backup',
        wrapper: 'winsw',
      );
      expect(reason == null, output == 'True');
    });
  }
  test('unknown account fails closed without starting elevation', () async {
    final process = _Process();
    final probe = ServiceAccountProbe(
      serviceName: 'BackupDatabaseService',
      processService: process,
    );
    expect(
      await probe.silentUpdateBlockReason(null, wrapper: 'winsw'),
      isNotNull,
    );
    verifyZeroInteractions(process);
  });
}
