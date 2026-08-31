import 'package:backup_database/infrastructure/external/system/windows_service/nssm_config_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NssmConfigPlan', () {
    late NssmConfigPlan plan;

    setUp(() {
      plan = NssmConfigPlan.build(
        appDir: r'C:\app',
        logPath: r'C:\logs',
      );
    });

    test('marks AppNoConsole and AppExit 77/78 as critical', () {
      bool isCritical(String key, List<String> values) {
        return plan.entries.any(
          (e) =>
              e.key == key &&
              e.values.length == values.length &&
              e.values.every((v) => values.contains(v)) &&
              e.critical,
        );
      }

      expect(isCritical('AppNoConsole', ['1']), isTrue);
      expect(isCritical('AppExit', ['77', 'Exit']), isTrue);
      expect(isCritical('AppExit', ['78', 'Exit']), isTrue);
      expect(isCritical('AppExit', ['Default', 'Restart']), isFalse);
    });

    test('elevated PowerShell sets use retry for critical keys', () {
      final snippet = plan.toElevatedPowerShellSets();
      expect(
        snippet,
        contains(
          "Set-NssmKeyWithRetry -KeyName \"AppExit\" -Values @('77', 'Exit')",
        ),
      );
      expect(
        snippet,
        contains(
          "Set-NssmKeyWithRetry -KeyName \"AppExit\" -Values @('78', 'Exit')",
        ),
      );
      expect(
        snippet,
        contains(
          "Set-NssmKeyWithRetry -KeyName \"AppNoConsole\" -Values @('1')",
        ),
      );
      expect(
        snippet,
        contains('Set-NssmKeyOptional -KeyName "DisplayName"'),
      );
    });
  });
}
