import 'dart:io';

import 'package:backup_database/core/config/environment_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Guard de CI contra **regressão do leak crítico** identificado na
/// auditoria 2026-05-28 (chave privada Ed25519 + senha admin em claro
/// no asset bundled).
///
/// Se este teste falhar, alguém comitou um valor em uma chave listada
/// em [EnvironmentLoader.forbiddenInBundledAssetKeys]. Esse valor vai
/// parar no `flutter_assets/.env` do instalador e qualquer cliente
/// consegue extrair via `unzip`. Resolva movendo o valor para
/// `C:\ProgramData\BackupDatabase\config\.env` (fora do repo) e
/// deixando a chave **vazia** no `.env` deste diretório.
void main() {
  test(
    '.env do repositório não contém valor para nenhuma '
    'forbiddenInBundledAssetKey',
    () async {
      final repoEnv = File(
        p.join(Directory.current.path, '.env'),
      );
      if (!await repoEnv.exists()) {
        // Repos clean checkout pode não ter `.env` (CI baixou só
        // `.env.example`). Nesse caso o teste é inerentemente OK.
        return;
      }

      final lines = await repoEnv.readAsLines();
      final offenders = <String, String>{};

      for (final raw in lines) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final eq = trimmed.indexOf('=');
        if (eq <= 0) continue;
        final key = trimmed.substring(0, eq).trim();
        final value = trimmed.substring(eq + 1).trim();
        if (value.isEmpty) continue;
        if (EnvironmentLoader.forbiddenInBundledAssetKeys.contains(key)) {
          offenders[key] = value;
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'SEGREDO no `.env` do repositório (bundled como asset Flutter).\n'
            'Chaves com valor não vazio que deveriam estar em branco:\n'
            '${offenders.keys.map((k) => "  - $k").join("\n")}\n\n'
            'Mova os valores para '
            r'`C:\ProgramData\BackupDatabase\config\.env`'
            ' e deixe vazio no `.env` do repo.',
      );
    },
  );

  test(
    '.env.example não contém valor para nenhuma '
    'forbiddenInBundledAssetKey (mesma regra que `.env`)',
    () async {
      final repoExample = File(
        p.join(Directory.current.path, '.env.example'),
      );
      if (!await repoExample.exists()) return;

      final lines = await repoExample.readAsLines();
      final offenders = <String, String>{};

      for (final raw in lines) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final eq = trimmed.indexOf('=');
        if (eq <= 0) continue;
        final key = trimmed.substring(0, eq).trim();
        final value = trimmed.substring(eq + 1).trim();
        if (value.isEmpty) continue;
        if (EnvironmentLoader.forbiddenInBundledAssetKeys.contains(key)) {
          offenders[key] = value;
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'SEGREDO em `.env.example` — esse arquivo é documentação '
            'pública. Deixe as chaves forbidden em branco:\n'
            '${offenders.keys.map((k) => "  - $k").join("\n")}',
      );
    },
  );
}
