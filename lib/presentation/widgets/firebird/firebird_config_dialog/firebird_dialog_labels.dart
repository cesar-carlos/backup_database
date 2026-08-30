import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:fluent_ui/fluent_ui.dart';

const int defaultFirebirdPort = 3050;

String firebirdVersionHintLabel(
  BuildContext context,
  FirebirdServerVersionHint v,
) {
  return switch (v) {
    FirebirdServerVersionHint.auto => appLocaleString(
      context,
      'Automático',
      'Automatic',
    ),
    FirebirdServerVersionHint.v25 => 'Firebird 2.5',
    FirebirdServerVersionHint.v30 => 'Firebird 3.0',
    FirebirdServerVersionHint.v40 => 'Firebird 4.0',
  };
}

String firebirdServiceManagerModeLabel(
  BuildContext context,
  FirebirdServiceManagerMode v,
) {
  return switch (v) {
    FirebirdServiceManagerMode.auto => appLocaleString(
      context,
      'Automático',
      'Automatic',
    ),
    FirebirdServiceManagerMode.always => appLocaleString(
      context,
      'Sempre usar',
      'Always use',
    ),
    FirebirdServiceManagerMode.never => appLocaleString(
      context,
      'Nunca usar',
      'Never use',
    ),
  };
}
