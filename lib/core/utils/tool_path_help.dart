/// Mensagens de ajuda para casos em que uma ferramenta CLI externa
/// (sqlcmd, pg_basebackup, dbisql, etc.) não foi localizada no PATH.
///
/// Antes desta classe a mensagem aparecia duplicada em três lugares
/// (`process_service.dart` em dois ramos e `postgres_backup_service.dart`).
/// Centralizar reduz risco de divergência e facilita ajustes textuais.
class ToolPathHelp {
  ToolPathHelp._();

  /// Conjunto de prefixos de executáveis associados ao PostgreSQL.
  static const Set<String> _postgresTools = {
    'psql',
    'pg_basebackup',
    'pg_verifybackup',
    'pg_restore',
    'pg_dump',
    'pg_receivewal',
  };

  /// Conjunto de prefixos de executáveis associados ao SQL Server.
  static const Set<String> _sqlServerTools = {'sqlcmd'};

  /// Conjunto de prefixos de executáveis associados ao Sybase SQL Anywhere.
  static const Set<String> _sybaseTools = {
    'dbisql',
    'dbbackup',
    'dbverify',
    'dbvalid',
  };

  /// Identifica a "família" da ferramenta a partir do nome do executável.
  /// Faz match por substring (case-insensitive) para tolerar caminhos com
  /// extensão (`pg_basebackup.exe`).
  static _ToolFamily _classify(String executable) {
    final lower = executable.toLowerCase();
    if (_postgresTools.any(lower.contains)) return _ToolFamily.postgres;
    if (_sqlServerTools.any(lower.contains)) return _ToolFamily.sqlServer;
    if (_sybaseTools.any(lower.contains)) return _ToolFamily.sybase;
    return _ToolFamily.unknown;
  }

  /// Devolve o nome canônico da ferramenta para PostgreSQL (best-effort).
  static String _postgresToolName(String executable) {
    final lower = executable.toLowerCase();
    for (final tool in _postgresTools) {
      if (lower.contains(tool)) return tool;
    }
    return 'psql';
  }

  /// Devolve o nome canônico da ferramenta para Sybase (best-effort).
  static String _sybaseToolName(String executable) {
    final lower = executable.toLowerCase();
    for (final tool in _sybaseTools) {
      if (lower.contains(tool)) return tool;
    }
    return 'dbverify';
  }

  /// Mensagem amigável de "ferramenta não encontrada no PATH" com instruções
  /// específicas para a família detectada (PostgreSQL, SQL Server, Sybase).
  ///
  /// Para executáveis desconhecidos retorna uma mensagem genérica.
  static String buildMessage(String executable) {
    switch (_classify(executable)) {
      case _ToolFamily.postgres:
        final tool = _postgresToolName(executable);
        return '$tool não encontrado no PATH do sistema.\n\n'
            'INSTRUÇÕES PARA ADICIONAR AO PATH:\n\n'
            '1. Localize a pasta bin do PostgreSQL instalado\n'
            '   (geralmente: C:\\Program Files\\PostgreSQL\\16\\bin)\n\n'
            '2. Adicione ao PATH do Windows:\n'
            '   - Pressione Win + X e selecione "Sistema"\n'
            '   - Clique em "Configurações avançadas do sistema"\n'
            '   - Na aba "Avançado", clique em "Variáveis de Ambiente"\n'
            '   - Em "Variáveis do sistema", encontre "Path" e clique em "Editar"\n'
            '   - Clique em "Novo" e adicione o caminho completo da pasta bin\n'
            '   - Clique em "OK" em todas as janelas\n\n'
            '3. Reinicie o aplicativo de backup\n\n'
            r'Consulte: docs\path_setup.md para mais detalhes.';

      case _ToolFamily.sqlServer:
        return 'sqlcmd não encontrado no PATH do sistema.\n\n'
            'O sqlcmd é uma ferramenta de linha de comando do SQL Server.\n\n'
            'OPÇÕES PARA RESOLVER:\n\n'
            'Opção 1: Instalar SQL Server Command Line Tools\n'
            '  - Baixe SQL Server Command Line Tools da Microsoft\n'
            '  - Durante a instalação, selecione "SQL Server Command Line Tools"\n'
            '  - O instalador configurará o PATH automaticamente\n\n'
            'Opção 2: Adicionar ao PATH manualmente\n'
            '  - Localize a pasta Tools\\Binn do SQL Server instalado\n'
            '    (ex: C:\\Program Files\\Microsoft SQL Server\\Client SDK\\ODBC\\170\\Tools\\Binn)\n'
            '  - Adicione ao PATH do Windows:\n'
            '    * Pressione Win + X → "Sistema"\n'
            '    * Clique em "Configurações avançadas do sistema"\n'
            '    * Na aba "Avançado", clique em "Variáveis de Ambiente"\n'
            '    * Em "Variáveis do sistema", encontre "Path" e clique em "Editar"\n'
            '    * Clique em "Novo" e adicione o caminho completo da pasta\n'
            '    * Clique em "OK" em todas as janelas\n\n'
            'Opção 3: Usar SQL Server Management Studio (SSMS)\n'
            '  - SSMS inclui sqlcmd\n'
            '  - Localize sqlcmd.exe na pasta do SSMS\n'
            '  - Adicione a pasta ao PATH conforme Opção 2\n\n'
            r'Consulte: docs\path_setup.md para mais detalhes.';

      case _ToolFamily.sybase:
        final tool = _sybaseToolName(executable);
        return '$tool não encontrado no PATH do sistema.\n\n'
            'As ferramentas do Sybase SQL Anywhere não estão disponíveis.\n\n'
            'OPÇÕES PARA RESOLVER:\n\n'
            'Opção 1: Adicionar ao PATH manualmente\n'
            '  - Localize a pasta Bin64 do SQL Anywhere instalado\n'
            '    (ex: C:\\Program Files\\SQL Anywhere 16\\Bin64)\n'
            '  - Adicione ao PATH do Windows:\n'
            '    * Pressione Win + X → "Sistema"\n'
            '    * Clique em "Configurações avançadas do sistema"\n'
            '    * Na aba "Avançado", clique em "Variáveis de Ambiente"\n'
            '    * Em "Variáveis do sistema", encontre "Path" e clique em "Editar"\n'
            '    * Clique em "Novo" e adicione o caminho completo da pasta Bin64\n'
            '    * Clique em "OK" em todas as janelas\n\n'
            'Opção 2: SQL Anywhere não instalado?\n'
            '  - Baixe e instale SQL Anywhere (versões 11, 12, 16 ou 17)\n'
            '  - Durante a instalação, selecione "Add to PATH"\n\n'
            r'Consulte: docs\path_setup.md para mais detalhes.';

      case _ToolFamily.unknown:
        return '$executable não encontrado no PATH do sistema.\n\n'
            'Verifique se a ferramenta está instalada e adicionada ao PATH.';
    }
  }

  /// Heurística para identificar se uma mensagem de erro indica que a
  /// ferramenta `toolName` não foi localizada (mensagens variam por shell e
  /// idioma). Usada por serviços que processam stdout/stderr de processos
  /// externos.
  static bool isToolNotFoundError(String errorMessageLower, String toolName) {
    final tool = toolName.toLowerCase();
    final hasToolReference =
        errorMessageLower.contains("'$tool'") ||
        errorMessageLower.contains(tool);
    final hasNotFoundMarker =
        errorMessageLower.contains('command not found') ||
        errorMessageLower.contains('not recognized') ||
        errorMessageLower.contains('nao e reconhecido') ||
        errorMessageLower.contains('nao reconhecido') ||
        errorMessageLower.contains('não é reconhecido') ||
        errorMessageLower.contains('não reconhecido') ||
        errorMessageLower.contains('nao encontrado') ||
        errorMessageLower.contains('nao foi encontrado') ||
        errorMessageLower.contains('não encontrado') ||
        errorMessageLower.contains('não foi encontrado') ||
        errorMessageLower.contains('cmdlet') ||
        errorMessageLower.contains('operable program') ||
        errorMessageLower.contains('script file') ||
        errorMessageLower.contains('programa operavel') ||
        errorMessageLower.contains('programa operável') ||
        errorMessageLower.contains('arquivo de script');

    return hasNotFoundMarker && hasToolReference;
  }
}

enum _ToolFamily { postgres, sqlServer, sybase, unknown }
