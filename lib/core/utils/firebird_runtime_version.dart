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

/// **Reservado para o roadmap de criptografia gbak completa.**
///
/// Em FB 4.0 o backup logico encriptado usa `gbak -KEYNAME` em
/// combinacao com `-CRYPT` e `-KEYHOLDER`. Em 2.5/3.0 nao existe
/// equivalente nativo (ver `gbak` manual: encryption switches foram
/// introduzidos em 3.0/4.0, **NUNCA `-key` sozinho**).
///
/// Este helper continua aqui — apesar de hoje **nao ter consumidor** —
/// como ponto de extensao para quando entrar o ticket de UI de
/// criptografia (`cryptPlugin`, `keyholder`, `keyName` no diálogo
/// Firebird). Auditoria 2026-05-27 removeu o consumidor original
/// (`_gbakCryptCliArgs` gerava comandos invalidos `-key`/`-KEYNAME
/// solto`); ver ADR-014.
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
