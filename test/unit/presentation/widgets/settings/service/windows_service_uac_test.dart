import 'package:backup_database/application/providers/windows_service_provider.dart';
import 'package:backup_database/presentation/widgets/settings/service/windows_service_uac.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isUacElevatedOperationType', () {
    test('returns true for install, uninstall, start, stop, restart', () {
      expect(
        isUacElevatedOperationType(WindowsServiceOperation.install),
        isTrue,
      );
      expect(
        isUacElevatedOperationType(WindowsServiceOperation.uninstall),
        isTrue,
      );
      expect(isUacElevatedOperationType(WindowsServiceOperation.start), isTrue);
      expect(isUacElevatedOperationType(WindowsServiceOperation.stop), isTrue);
      expect(
        isUacElevatedOperationType(WindowsServiceOperation.restart),
        isTrue,
      );
    });

    test('returns false for check and none', () {
      expect(
        isUacElevatedOperationType(WindowsServiceOperation.check),
        isFalse,
      );
      expect(isUacElevatedOperationType(WindowsServiceOperation.none), isFalse);
    });
  });
}
