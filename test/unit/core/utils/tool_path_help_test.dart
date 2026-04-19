import 'package:backup_database/core/utils/tool_path_help.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolPathHelp.buildMessage — PostgreSQL family', () {
    test('classifies psql', () {
      final msg = ToolPathHelp.buildMessage('psql');
      expect(msg, startsWith('psql não encontrado no PATH'));
      expect(msg, contains('PostgreSQL'));
    });

    test('classifies pg_basebackup', () {
      final msg = ToolPathHelp.buildMessage('pg_basebackup');
      expect(msg, startsWith('pg_basebackup não encontrado no PATH'));
      expect(msg, contains('PostgreSQL'));
    });

    test('classifies pg_basebackup.exe (with extension)', () {
      final msg = ToolPathHelp.buildMessage('pg_basebackup.exe');
      // Match por substring: tolerar `.exe` na ponta
      expect(msg, contains('PostgreSQL'));
    });

    test('classifies absolute paths case-insensitively', () {
      final msg = ToolPathHelp.buildMessage(
        r'C:\Program Files\PostgreSQL\16\bin\PSQL.EXE',
      );
      expect(msg, contains('PostgreSQL'));
    });

    test('returns canonical tool name even when path includes other text', () {
      final msg = ToolPathHelp.buildMessage(
        r'C:\program files\PostgreSQL\bin\pg_verifybackup',
      );
      expect(msg, startsWith('pg_verifybackup'));
    });
  });

  group('ToolPathHelp.buildMessage — SQL Server family', () {
    test('classifies sqlcmd', () {
      final msg = ToolPathHelp.buildMessage('sqlcmd');
      expect(msg, startsWith('sqlcmd não encontrado no PATH'));
      expect(msg, contains('SQL Server'));
    });

    test('classifies sqlcmd.exe', () {
      final msg = ToolPathHelp.buildMessage('SQLCMD.EXE');
      expect(msg, contains('SQL Server'));
    });
  });

  group('ToolPathHelp.buildMessage — Sybase family', () {
    test('classifies dbisql', () {
      final msg = ToolPathHelp.buildMessage('dbisql');
      expect(msg, startsWith('dbisql não encontrado'));
      expect(msg, contains('SQL Anywhere'));
    });

    test('classifies dbbackup', () {
      final msg = ToolPathHelp.buildMessage('dbbackup');
      expect(msg, startsWith('dbbackup não encontrado'));
    });

    test('classifies dbverify', () {
      final msg = ToolPathHelp.buildMessage('dbverify.exe');
      expect(msg, contains('SQL Anywhere'));
    });
  });

  group('ToolPathHelp.buildMessage — unknown family', () {
    test('returns generic message for unknown executable', () {
      final msg = ToolPathHelp.buildMessage('foobar');
      expect(msg, startsWith('foobar não encontrado no PATH'));
      expect(
        msg,
        isNot(contains('PostgreSQL')),
        reason: 'unknown should NOT mention specific DB vendors',
      );
      expect(msg, isNot(contains('SQL Server')));
    });
  });

  group('ToolPathHelp.isToolNotFoundError', () {
    test('detects PowerShell English "not recognized" with tool name', () {
      const msg = "the term 'sqlcmd' is not recognized as the name of a cmdlet";
      expect(
        ToolPathHelp.isToolNotFoundError(msg, 'sqlcmd'),
        isTrue,
      );
    });

    test('detects PowerShell Portuguese "nao e reconhecido"', () {
      const msg =
          "o termo 'sqlcmd' nao e reconhecido como nome de cmdlet, "
          'funcao, arquivo de script ou programa operavel';
      expect(
        ToolPathHelp.isToolNotFoundError(msg, 'sqlcmd'),
        isTrue,
      );
    });

    test('detects bash-style "command not found"', () {
      const msg = 'bash: psql: command not found';
      expect(ToolPathHelp.isToolNotFoundError(msg, 'psql'), isTrue);
    });

    test('detects "nao encontrado" (Portuguese plain)', () {
      const msg = 'pg_basebackup: nao encontrado';
      expect(
        ToolPathHelp.isToolNotFoundError(msg, 'pg_basebackup'),
        isTrue,
      );
    });

    test('returns false when both markers are present but tool name absent', () {
      const msg = "the term 'foo' is not recognized as the name of a cmdlet";
      expect(
        ToolPathHelp.isToolNotFoundError(msg, 'sqlcmd'),
        isFalse,
        reason:
            'must require BOTH a not-found marker AND the tool name to '
            'avoid false positives on unrelated errors',
      );
    });

    test('returns false when tool name is present but no not-found marker', () {
      const msg = 'sqlcmd: connection refused';
      expect(
        ToolPathHelp.isToolNotFoundError(msg, 'sqlcmd'),
        isFalse,
        reason: 'connection errors should NOT be classified as not-found',
      );
    });

    test('returns false for empty message', () {
      expect(ToolPathHelp.isToolNotFoundError('', 'sqlcmd'), isFalse);
    });

    test(
      'detects tool name regardless of quoting (with or without single quotes)',
      () {
        const withQuotes = "the term 'psql' is not recognized";
        const withoutQuotes = 'psql command not found';
        expect(
          ToolPathHelp.isToolNotFoundError(withQuotes, 'psql'),
          isTrue,
        );
        expect(
          ToolPathHelp.isToolNotFoundError(withoutQuotes, 'psql'),
          isTrue,
        );
      },
    );
  });
}
