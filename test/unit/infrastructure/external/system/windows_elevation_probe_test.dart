import 'package:backup_database/infrastructure/external/system/windows_elevation_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowsElevationProbe.parseProbeOutput', () {
    test('parses canonical happy path uac=true|elevated=true', () {
      final snapshot = WindowsElevationProbe.parseProbeOutput(
        'uac=true|elevated=true\n',
      );

      expect(snapshot.uacEnabled, isTrue);
      expect(snapshot.processIsElevated, isTrue);
      expect(snapshot.wouldTriggerUacPrompt, isFalse);
    });

    test(
      'wouldTriggerUacPrompt only when UAC on AND process NOT elevated',
      () {
        final on = WindowsElevationProbe.parseProbeOutput(
          'uac=true|elevated=false',
        );
        expect(on.wouldTriggerUacPrompt, isTrue);

        final elevated = WindowsElevationProbe.parseProbeOutput(
          'uac=true|elevated=true',
        );
        expect(elevated.wouldTriggerUacPrompt, isFalse);

        final off = WindowsElevationProbe.parseProbeOutput(
          'uac=false|elevated=false',
        );
        expect(off.wouldTriggerUacPrompt, isFalse);

        final offElev = WindowsElevationProbe.parseProbeOutput(
          'uac=false|elevated=true',
        );
        expect(offElev.wouldTriggerUacPrompt, isFalse);
      },
    );

    test(
      'null in any of the two bits is treated as "unknown" → NOT triggering',
      () {
        // Defesa conservadora documentada no `ElevationSnapshot`: quando
        // a detecção é frágil, preferimos correr o risco de um prompt
        // UAC silencioso do que bloquear update legítimo.
        final unknownUac = WindowsElevationProbe.parseProbeOutput(
          'uac=null|elevated=false',
        );
        expect(unknownUac.uacEnabled, isNull);
        expect(unknownUac.wouldTriggerUacPrompt, isFalse);

        final unknownElev = WindowsElevationProbe.parseProbeOutput(
          'uac=true|elevated=null',
        );
        expect(unknownElev.processIsElevated, isNull);
        expect(unknownElev.wouldTriggerUacPrompt, isFalse);
      },
    );

    test('tolerates leading log lines and whitespace', () {
      final snapshot = WindowsElevationProbe.parseProbeOutput(
        '  some PS verbose output\n'
        '\r\n'
        '  uac=true|elevated=true  \n',
      );
      expect(snapshot.uacEnabled, isTrue);
      expect(snapshot.processIsElevated, isTrue);
    });

    test('marker absent → snapshot null/null with diagnostic', () {
      final snapshot = WindowsElevationProbe.parseProbeOutput(
        'garbled output that does not contain the marker\n',
      );
      expect(snapshot.uacEnabled, isNull);
      expect(snapshot.processIsElevated, isNull);
      expect(snapshot.diagnostic, 'output-missing-marker');
    });

    test('unknown values default to null without crashing', () {
      final snapshot = WindowsElevationProbe.parseProbeOutput(
        'uac=maybe|elevated=42',
      );
      expect(snapshot.uacEnabled, isNull);
      expect(snapshot.processIsElevated, isNull);
    });

    test('probeScript references the registry path used by Windows UAC', () {
      // Guardrail: se mexer no script, garantir que o caminho oficial
      // documentado pela Microsoft continua sendo lido.
      expect(
        WindowsElevationProbe.probeScript,
        contains(
          r'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System',
        ),
      );
      expect(WindowsElevationProbe.probeScript, contains('EnableLUA'));
      expect(
        WindowsElevationProbe.probeScript,
        contains('WindowsBuiltInRole]::Administrator'),
      );
    });
  });
}
