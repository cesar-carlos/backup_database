import 'dart:io';

import 'package:crypto/crypto.dart';

const _sha256HexLength = 64;

/// Result of verifying a file against its SHA-256 sidecar.
sealed class Sha256VerificationResult {
  const Sha256VerificationResult();
}

class Sha256VerificationOk extends Sha256VerificationResult {
  const Sha256VerificationOk({
    required this.hash,
    required this.fileSize,
    required this.durationMs,
  });
  final String hash;
  final int fileSize;
  final int durationMs;
}

class Sha256VerificationFailure extends Sha256VerificationResult {
  const Sha256VerificationFailure(this.message);
  final String message;
}

/// Verifies a file against its `.sha256` sidecar (format: `{hash}  {filename}`).
///
/// Use after downloading a backup from FTP to confirm integrity before restore.
/// Sidecar path defaults to `{filePath}.sha256` if not specified.
Future<Sha256VerificationResult> verifyFileSha256(
  String filePath, {
  String? sidecarPath,
}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    return Sha256VerificationFailure('Arquivo não encontrado: $filePath');
  }

  final effectiveSidecarPath = sidecarPath ?? '$filePath.sha256';
  final sidecarFile = File(effectiveSidecarPath);
  if (!await sidecarFile.exists()) {
    return Sha256VerificationFailure(
      'Arquivo sidecar não encontrado: $effectiveSidecarPath. '
      'Baixe o .sha256 junto com o backup do FTP.',
    );
  }

  final sidecarContent = await sidecarFile.readAsString();
  final expectedHash = _parseExpectedHash(sidecarContent);
  if (expectedHash == null || expectedHash.length != _sha256HexLength) {
    return Sha256VerificationFailure(
      'Sidecar inválido ou formato não reconhecido: $effectiveSidecarPath',
    );
  }

  final stopwatch = Stopwatch()..start();
  String actualHash;
  try {
    final digest = await sha256.bind(file.openRead()).first;
    actualHash = digest.toString();
  } on Object catch (e) {
    return Sha256VerificationFailure('Erro ao calcular hash: $e');
  }
  stopwatch.stop();

  if (actualHash.toLowerCase() != expectedHash.toLowerCase()) {
    return Sha256VerificationFailure(
      'Integridade falhou. Hash esperado: $expectedHash, calculado: $actualHash. '
      'O arquivo pode estar corrompido.',
    );
  }

  final fileSize = await file.length();
  return Sha256VerificationOk(
    hash: actualHash,
    fileSize: fileSize,
    durationMs: stopwatch.elapsedMilliseconds,
  );
}

String? _parseExpectedHash(String sidecarContent) {
  final trimmed = sidecarContent.trim();
  if (trimmed.length < _sha256HexLength) return null;

  final hashPart = trimmed.substring(0, _sha256HexLength);
  if (!RegExp(r'^[a-fA-F0-9]+$').hasMatch(hashPart)) return null;

  return hashPart;
}
