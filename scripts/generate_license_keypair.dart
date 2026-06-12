// Script utilitário só roda em terminal; `print`/`stderr` são a forma
// natural de expor output para o operador.
// ignore_for_file: avoid_print
//
// Gera um novo par de chaves Ed25519 para licenciamento.
//
// Uso:
//   dart run scripts/generate_license_keypair.dart [keyId]
//
// `keyId` é opcional (default: `ed25519-N` onde N é o timestamp). Use
// um id descritivo (ex.: `ed25519-2`) quando estiver fazendo rotação
// graceful da chave atual.
//
// O script imprime:
// 1. **Public key** (32 bytes base64) — vai no `.env` do **repositório**
//    (asset bundled). Em rotação, adicione no JSON
//    `BACKUP_DATABASE_LICENSE_PUBLIC_KEYS` mantendo a chave antiga.
// 2. **Private key** (64 bytes base64) — vai APENAS no `.env` **externo**
//    (C:\ProgramData\BackupDatabase\config\.env). NUNCA comite.
// 3. Instruções de configuração e plano de rotação.
//
// Veja `docs/onboarding/licenciamento.md` para o procedimento completo
// de rotação.
import 'dart:convert';
import 'dart:io';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

void main(List<String> args) {
  final keyId = args.isNotEmpty
      ? args.first.trim()
      : 'ed25519-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';

  if (keyId.isEmpty) {
    stderr.writeln('Erro: keyId não pode ser vazio.');
    exit(64);
  }

  final pair = ed.generateKey();
  final publicBase64 = base64.encode(pair.publicKey.bytes);
  final privateBase64 = base64.encode(pair.privateKey.bytes);

  print('keyId           : $keyId');
  print('publicKeyBase64 : $publicBase64');
  print('privateKeyBase64: $privateBase64');

  stderr
    ..writeln()
    ..writeln('─' * 70)
    ..writeln('PASSOS DE CONFIGURAÇÃO')
    ..writeln('─' * 70)
    ..writeln()
    ..writeln('1) PUBLIC KEY (vai no asset bundled `.env` do repositório).')
    ..writeln('   Caso de uso A — primeira chave (sem licenças anteriores):')
    ..writeln()
    ..writeln('     BACKUP_DATABASE_LICENSE_PUBLIC_KEY=$publicBase64')
    ..writeln()
    ..writeln('   Caso de uso B — rotação (manter chave antiga válida):')
    ..writeln()
    ..writeln('     BACKUP_DATABASE_LICENSE_PUBLIC_KEYS={')
    ..writeln('       "ed25519-1": "<chave_antiga_base64>",')
    ..writeln('       "$keyId": "$publicBase64"')
    ..writeln('     }')
    ..writeln()
    ..writeln('   (JSON em uma linha, sem espaços extras.)')
    ..writeln()
    ..writeln(
      r'2) PRIVATE KEY — apenas em C:\ProgramData\BackupDatabase\config\.env',
    )
    ..writeln('   (NUNCA no `.env` do repositório):')
    ..writeln()
    ..writeln('     BACKUP_DATABASE_LICENSE_PRIVATE_KEY=$privateBase64')
    ..writeln('     BACKUP_DATABASE_LICENSE_ACTIVE_KEY_ID=$keyId')
    ..writeln()
    ..writeln('3) Verificação: reinicie o app em modo dev. O log deve mostrar:')
    ..writeln()
    ..writeln(
      '   LicenseGenerationService initialized with activeKeyId="$keyId"',
    )
    ..writeln('   (decoder accepts: <lista incluindo $keyId>)')
    ..writeln()
    ..writeln('4) Para rotação completa, depois que todos os clientes')
    ..writeln('   atualizarem o build com o JSON múltiplas-chaves:')
    ..writeln('   a) Re-emita licenças ativas usando ACTIVE_KEY_ID=$keyId.')
    ..writeln(
      '   b) Quando todos os clientes tiverem licenças com keyId="$keyId",',
    )
    ..writeln('      remova a entrada antiga do JSON PUBLIC_KEYS.')
    ..writeln()
    ..writeln('─' * 70);
}
