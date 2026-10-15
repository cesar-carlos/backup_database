import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_account_config.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_nssm_configurator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockProcessService extends Mock implements ProcessService {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(Duration.zero);
  });

  test(
    'configure does not put the service password on a process command line',
    () async {
      const secret = 'S3cret-Pa55-not-in-argv!';
      final process = _MockProcessService();
      final captured = <List<String>>[];
      String? seenPassword;
      when(
        () => process.run(
          executable: any(named: 'executable'),
          arguments: any(named: 'arguments'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((invocation) async {
        final arguments =
            invocation.namedArguments[#arguments]! as List<String>;
        captured.add(List<String>.from(arguments));
        return const rd.Success(
          ProcessResult(
            exitCode: 0,
            stdout: '',
            stderr: '',
            duration: Duration.zero,
          ),
        );
      });

      final configurator = WindowsServiceNssmConfigurator(
        processService: process,
        accountConfig: WindowsServiceAccountConfig(
          changeAccount:
              ({
                required String serviceName,
                required String serviceUser,
                required String servicePassword,
              }) {
                expect(serviceName, 'BackupDatabaseService');
                expect(serviceUser, r'CONTOSO\backupsvc');
                seenPassword = servicePassword;
                return 0;
              },
        ),
      );

      final result = await configurator.configure(
        nssmPath: r'C:\tools\nssm.exe',
        serviceUser: r'CONTOSO\backupsvc',
        servicePassword: secret,
      );

      expect(result.isSuccess(), isTrue);
      expect(seenPassword, secret);
      expect(captured, isNotEmpty);
      for (final arguments in captured) {
        expect(arguments.join(' ').contains(secret), isFalse);
        expect(arguments, isNot(contains('ObjectName')));
      }
    },
  );

  test('account config failure does not include the password', () async {
    const secret = 'S3cret-Pa55-not-in-argv!';
    final config = WindowsServiceAccountConfig(
      changeAccount:
          ({
            required String serviceName,
            required String serviceUser,
            required String servicePassword,
          }) {
            expect(serviceName, isNotEmpty);
            expect(serviceUser, isNotEmpty);
            expect(servicePassword, secret);
            return 5;
          },
    );

    final result = await config.setLogonAccount(
      serviceName: 'BackupDatabaseService',
      serviceUser: r'CONTOSO\backupsvc',
      servicePassword: secret,
    );

    final failure = result.exceptionOrNull();
    expect(failure, isNotNull);
    expect(failure.toString().contains(secret), isFalse);
    expect(failure.toString(), contains('5'));
  });
}
