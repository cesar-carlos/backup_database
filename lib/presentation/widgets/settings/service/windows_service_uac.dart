import 'package:backup_database/application/providers/windows_service_provider.dart';

bool isUacElevatedOperationType(WindowsServiceOperation operation) {
  return operation == WindowsServiceOperation.install ||
      operation == WindowsServiceOperation.uninstall ||
      operation == WindowsServiceOperation.start ||
      operation == WindowsServiceOperation.stop ||
      operation == WindowsServiceOperation.restart;
}
