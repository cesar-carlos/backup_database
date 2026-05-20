import 'dart:async';

import 'package:backup_database/presentation/boot/boot.dart';

void main() {
  runZonedGuarded(
    () => unawaited(AppBootstrap.run()),
    AppBootstrap.handleUnhandledError,
  );
}
