import 'dart:io';

import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:path/path.dart' as p;

/// Contrato de persistência best-effort para o marcador anti-rollback
/// do `SignedRevocationListService`. Veja
/// `architectural_patterns.mdc §5.5` para o problema de fundo (rollback
/// de revocation list assinada).
abstract class RevocationListIssuedAtStore {
  Future<DateTime?> load();
  Future<void> save(DateTime issuedAt);
}

/// Persiste em arquivo simples no diretório de dados da máquina.
/// **Não** é atômico — best-effort por design (anti-rollback é defesa
/// em profundidade, não a única camada de segurança). A escrita usa
/// `WriteMode.write` para sobrescrever; uma falha no meio do write
/// pode deixar o arquivo vazio, que se hidrata como `null` no próximo
/// load (recomeça do zero — pior cenário é aceitar uma CRL retroativa
/// uma vez antes de re-avançar o marcador).
class FileRevocationListIssuedAtStore implements RevocationListIssuedAtStore {
  FileRevocationListIssuedAtStore({
    String fileName = 'revocation_issued_at.txt',
  }) : _fileName = fileName;

  static const String defaultFileName = 'revocation_issued_at.txt';
  final String _fileName;

  Future<File> _resolveFile() async {
    final dir = await resolveMachineDataDirectory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, _fileName));
  }

  @override
  Future<DateTime?> load() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return null;
      final raw = (await file.readAsString()).trim();
      if (raw.isEmpty) return null;
      return DateTime.parse(raw);
    } on Object catch (e, s) {
      LoggerService.warning(
        'FileRevocationListIssuedAtStore.load falhou (best-effort): $e',
        e,
        s,
      );
      return null;
    }
  }

  @override
  Future<void> save(DateTime issuedAt) async {
    try {
      final file = await _resolveFile();
      await file.writeAsString(
        issuedAt.toUtc().toIso8601String(),
        flush: true,
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        'FileRevocationListIssuedAtStore.save falhou (best-effort): $e',
        e,
        s,
      );
    }
  }
}
