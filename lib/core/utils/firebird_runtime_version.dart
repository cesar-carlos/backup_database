import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';

bool firebirdRuntimeIsVersion4OrNewer({
  required FirebirdServerVersionHint serverVersionHint,
  String? gbakWiTagline,
}) {
  switch (serverVersionHint) {
    case FirebirdServerVersionHint.v40:
      return true;
    case FirebirdServerVersionHint.v25:
    case FirebirdServerVersionHint.v30:
      return false;
    case FirebirdServerVersionHint.auto:
      return firebirdGbakTaglineImpliesMajorVersion(
        gbakWiTagline,
        minimumMajor: 4,
      );
  }
}

bool firebirdRuntimeSupportsNbackupGuidMode({
  required FirebirdServerVersionHint serverVersionHint,
  String? gbakWiTagline,
}) {
  return firebirdRuntimeIsVersion4OrNewer(
    serverVersionHint: serverVersionHint,
    gbakWiTagline: gbakWiTagline,
  );
}

/// Firebird 4 native encryption uses `gbak -KEYNAME`; 2.5/3.0 use `-key`.
bool firebirdGbakUsesKeyNameEncryption({
  required FirebirdServerVersionHint serverVersionHint,
  String? gbakWiTagline,
}) {
  return firebirdRuntimeIsVersion4OrNewer(
    serverVersionHint: serverVersionHint,
    gbakWiTagline: gbakWiTagline,
  );
}

bool firebirdGbakTaglineImpliesMajorVersion(
  String? gbakWiTagline, {
  required int minimumMajor,
}) {
  final tag = gbakWiTagline?.trim();
  if (tag == null || tag.isEmpty) {
    return false;
  }
  final match = RegExp(
    r'WI-V(\d+)',
    caseSensitive: false,
  ).firstMatch(tag);
  if (match == null) {
    return false;
  }
  final major = int.tryParse(match.group(1)!);
  if (major == null) {
    return false;
  }
  return major >= minimumMajor;
}
