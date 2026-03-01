// ignore_for_file: avoid_print - script CLI usa print para saída ao usuário
//
// Utilitário para verificar integridade de arquivos baixados do FTP
// antes do restore. Use após baixar o backup e seu sidecar .sha256.
//
// Uso: dart run bin/verify_sha256.dart <caminho-do-arquivo>
//
// Exemplo:
//   dart run bin/verify_sha256.dart C:\Downloads\backup_2026-03-01.db
//
// O sidecar deve estar no mesmo diretório: backup_2026-03-01.db.sha256

import 'dart:io';

import 'package:backup_database/core/utils/sha256_verifier.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Uso: dart run bin/verify_sha256.dart <caminho-do-arquivo>');
    print('');
    print('Verifica a integridade do arquivo contra o sidecar .sha256');
    print('(formato gerado pelo backup ao enviar para FTP).');
    exit(1);
  }

  final filePath = args.first;
  final result = await verifyFileSha256(filePath);

  switch (result) {
    case Sha256VerificationOk(:final hash, :final fileSize, :final durationMs):
      final sizeMb = (fileSize / (1024 * 1024)).toStringAsFixed(1);
      print('OK - Integridade verificada');
      print('  Hash: $hash');
      print('  Tamanho: ${sizeMb}MB');
      print('  Tempo: ${durationMs}ms');
      exit(0);
    case Sha256VerificationFailure(:final message):
      print('ERRO: $message');
      exit(1);
  }
}
