// Script utilitário só roda em terminal; `print` é a forma natural de
// expor o output para o operador.
// ignore_for_file: avoid_print
//
// Gera o hash da senha admin para o gerador de licenças.
//
// Uso:
//   dart run scripts/hash_admin_password.dart <senha>
//
// O resultado tem o formato `pbkdf2-sha256$<iters>$<salt>$<hash>` e deve
// ser colocado em `LICENSE_ADMIN_PASSWORD_HASH` no arquivo `.env`
// externo (C:\ProgramData\BackupDatabase\config\.env). **Nunca** comite
// nem o hash nem a senha no `.env` do repositório — o asset bundled é
// distribuído aos clientes.
import 'dart:io';

import 'package:backup_database/application/services/admin_password_verifier.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Uso: dart run scripts/hash_admin_password.dart <senha>');
    exit(64);
  }
  final password = args.first;
  if (password.length < 8) {
    stderr.writeln(
      'Senha muito curta. Mínimo recomendado: 12 caracteres.',
    );
  }
  final encoded = AdminPasswordVerifier.encodeForStorage(
    password: password,
  );
  print(encoded);
  stderr
    ..writeln()
    ..writeln('Adicione esta linha em:')
    ..writeln(r'  C:\ProgramData\BackupDatabase\config\.env')
    ..writeln()
    ..writeln('LICENSE_ADMIN_PASSWORD_HASH=$encoded');
}
