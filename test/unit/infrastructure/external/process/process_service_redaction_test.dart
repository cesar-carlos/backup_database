import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProcessService redacao de segredo', () {
    test('redactCommandForLogging redige -P <valor> (SQL Server)', () {
      final result = ProcessService.redactCommandForLogging(
        'sqlcmd',
        [
          '-S',
          'localhost',
          '-U',
          'sa',
          '-P',
          'mySecretPassword',
          '-Q',
          'SELECT 1',
        ],
      );

      expect(result, contains('***REDACTED***'));
      expect(result, isNot(contains('mySecretPassword')));
      expect(result, contains('-P'));
    });

    test(
      'redactCommandForLogging redige PWD= em connection strings (Sybase)',
      () {
        const connStr =
            'ENG=TestServer;DBN=testdb;UID=dba;PWD=superSecret123;LINKS=TCPIP';
        final result = ProcessService.redactCommandForLogging(
          'dbisql',
          ['-c', connStr, '-nogui', 'SELECT 1'],
        );

        expect(result, contains('PWD=***REDACTED***'));
        expect(result, isNot(contains('superSecret123')));
        expect(result, contains('ENG=TestServer'));
        expect(result, contains('UID=dba'));
      },
    );

    test('redactCommandForLogging redige PWD= case insensitive', () {
      const connStr = 'ENG=x;pwd=lowercaseSecret;DBN=db';
      final result = ProcessService.redactCommandForLogging(
        'dbbackup',
        ['-c', connStr, '-y', '/path'],
      );

      expect(result, contains('***REDACTED***'));
      expect(result, isNot(contains('lowercaseSecret')));
    });

    test('redactCommandForLogging preserva argumentos nao sensiveis', () {
      final result = ProcessService.redactCommandForLogging(
        'dbvalid',
        ['-c', 'UID=dba;DBF=/path/to/file.db'],
      );

      expect(result, contains('UID=dba'));
      expect(result, contains('/path/to/file.db'));
    });

    test('redactEnvForLogging redige SQLCMDPASSWORD', () {
      final env = {
        'PATH': '/usr/bin',
        'SQLCMDPASSWORD': 'sqlSecret',
      };
      final result = ProcessService.redactEnvForLogging(env);

      expect(result, contains('SQLCMDPASSWORD=***REDACTED***'));
      expect(result, isNot(contains('sqlSecret')));
    });

    test('redactEnvForLogging redige PGPASSWORD', () {
      final env = {'PGPASSWORD': 'pgSecret'};
      final result = ProcessService.redactEnvForLogging(env);

      expect(result, contains('PGPASSWORD=***REDACTED***'));
      expect(result, isNot(contains('pgSecret')));
    });

    test('redactCommandForLogging redige -password <valor> (Firebird gbak)', () {
      final result = ProcessService.redactCommandForLogging(
        'gbak',
        [
          '-b',
          '-user',
          'SYSDBA',
          '-password',
          'masterkey',
          r'C:\data\db.fdb',
          r'C:\backup\db.fbk',
        ],
      );

      expect(result, contains('***REDACTED***'));
      expect(result, isNot(contains('masterkey')));
      expect(result, contains('-password'));
    });

    test('redactCommandForLogging redige -pas <valor> (Firebird)', () {
      final result = ProcessService.redactCommandForLogging(
        'isql',
        ['-pas', 'fbSecret', '-q', 'quit'],
      );

      expect(result, contains('***REDACTED***'));
      expect(result, isNot(contains('fbSecret')));
    });

    test('redactCommandForLogging redige -PASSWORD case insensitive', () {
      final result = ProcessService.redactCommandForLogging(
        'gbak',
        ['-PASSWORD', 'CaseTest', '-b', 'x.fdb', 'y.fbk'],
      );

      expect(result, contains('***REDACTED***'));
      expect(result, isNot(contains('CaseTest')));
    });

    test('redactEnvForLogging redige FIREBIRD_PASSWORD e ISC_PASSWORD', () {
      final env = {
        'FIREBIRD_PASSWORD': 'fbEnv',
        'ISC_PASSWORD': 'iscEnv',
        'PATH': r'C:\bin',
      };
      final result = ProcessService.redactEnvForLogging(env);

      expect(result, contains('FIREBIRD_PASSWORD=***REDACTED***'));
      expect(result, contains('ISC_PASSWORD=***REDACTED***'));
      expect(result, isNot(contains('fbEnv')));
      expect(result, isNot(contains('iscEnv')));
    });

    test('redactEnvForLogging retorna vazio para env null ou vazio', () {
      expect(ProcessService.redactEnvForLogging(null), isEmpty);
      expect(ProcessService.redactEnvForLogging({}), isEmpty);
    });
  });
}
