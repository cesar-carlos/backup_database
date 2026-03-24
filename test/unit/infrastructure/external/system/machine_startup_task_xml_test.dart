import 'package:backup_database/infrastructure/external/system/machine_startup_task_xml.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildMachineLogonStartupTaskXml', () {
    test('should escape XML special characters in command and arguments', () {
      final xml = buildMachineLogonStartupTaskXml(
        command: r'C:\Apps\a&b\app.exe',
        arguments: '--x "<tag>"',
      );

      expect(xml, contains('&amp;'));
      expect(xml, contains('&lt;tag&gt;'));
      expect(xml, isNot(contains('a&b')));
    });

    test('should include logon trigger and task path URI', () {
      final xml = buildMachineLogonStartupTaskXml(
        command: r'C:\Apps\Backup.exe',
        arguments: '--startup-launch',
      );

      expect(xml, contains('<LogonTrigger>'));
      expect(xml, contains(r'\BackupDatabase\MachineStartup'));
      expect(xml, contains('--startup-launch'));
    });
  });

  group('escapeXmlForMachineStartupTask', () {
    test('should escape ampersand before other replacements', () {
      expect(
        escapeXmlForMachineStartupTask('a & b'),
        equals('a &amp; b'),
      );
    });
  });
}
