/// Mensagens de ajuda para casos em que uma ferramenta CLI externa
/// (sqlcmd, pg_basebackup, dbisql, etc.) não foi localizada no PATH.
///
/// Antes desta classe a mensagem aparecia duplicada em três lugares
/// (`process_service.dart` em dois ramos e `postgres_backup_service.dart`).
/// Centralizar reduz risco de divergência e facilita ajustes textuais.
abstract final class ToolPathHelp {
  /// Famílias de ferramentas suportadas, na ordem de classificação. A
  /// ordem importa: `dbisql` deve casar Sybase antes de bater no `isql`
  /// substring do Firebird. Para preservar isso, `_classify` percorre
  /// a lista nessa sequência.
  static const List<_ToolHelpEntry> _entries = <_ToolHelpEntry>[
    _ToolHelpEntry(
      family: _ToolFamily.postgres,
      knownTools: <String>{
        'psql',
        'pg_basebackup',
        'pg_verifybackup',
        'pg_restore',
        'pg_dump',
        'pg_receivewal',
      },
      defaultCanonicalName: 'psql',
      messageBuilder: _postgresMessage,
    ),
    _ToolHelpEntry(
      family: _ToolFamily.sqlServer,
      knownTools: <String>{'sqlcmd'},
      defaultCanonicalName: 'sqlcmd',
      messageBuilder: _sqlServerMessage,
    ),
    _ToolHelpEntry(
      family: _ToolFamily.sybase,
      knownTools: <String>{
        'dbisql',
        'dbbackup',
        'dbverify',
        'dbvalid',
      },
      defaultCanonicalName: 'dbverify',
      messageBuilder: _sybaseMessage,
    ),
    _ToolHelpEntry(
      family: _ToolFamily.firebird,
      knownTools: <String>{
        'gbak',
        'nbackup',
        'gstat',
        'isql',
        'isql-fb',
      },
      defaultCanonicalName: 'gbak',
      messageBuilder: _firebirdMessage,
    ),
  ];

  static _ToolHelpEntry? _classify(String executable) {
    final lower = executable.toLowerCase();
    for (final entry in _entries) {
      if (entry.knownTools.any(lower.contains)) {
        return entry;
      }
    }
    return null;
  }

  static String _canonicalToolName(_ToolHelpEntry entry, String executable) {
    final lower = executable.toLowerCase();
    for (final tool in entry.knownTools) {
      if (lower.contains(tool)) return tool;
    }
    return entry.defaultCanonicalName;
  }

  /// Mensagem amigável de "ferramenta não encontrada no PATH" com
  /// instruções específicas para a família detectada (PostgreSQL,
  /// SQL Server, Sybase, Firebird). Para executáveis desconhecidos
  /// retorna uma mensagem genérica.
  static String buildMessage(String executable) {
    final entry = _classify(executable);
    if (entry == null) {
      return '$executable não encontrado no PATH do sistema.\n\n'
          'Verifique se a ferramenta está instalada e adicionada ao PATH.';
    }
    return entry.messageBuilder(_canonicalToolName(entry, executable));
  }

  /// Heurística para identificar se uma mensagem de erro indica que a
  /// ferramenta `toolName` não foi localizada (mensagens variam por
  /// shell e idioma). Usada por serviços que processam stdout/stderr
  /// de processos externos.
  static bool isToolNotFoundError(String errorMessageLower, String toolName) {
    final tool = toolName.toLowerCase();
    final hasToolReference =
        errorMessageLower.contains("'$tool'") ||
        errorMessageLower.contains(tool);
    if (!hasToolReference) return false;

    for (final marker in _notFoundMarkers) {
      if (errorMessageLower.contains(marker)) return true;
    }
    return false;
  }

  static const List<String> _notFoundMarkers = <String>[
    'command not found',
    'not recognized',
    'nao e reconhecido',
    'nao reconhecido',
    'não é reconhecido',
    'não reconhecido',
    'nao encontrado',
    'nao foi encontrado',
    'não encontrado',
    'não foi encontrado',
    'cmdlet',
    'operable program',
    'script file',
    'programa operavel',
    'programa operável',
    'arquivo de script',
  ];

  // ==========================================================================
  // Templates de mensagem por família. Mantidos como funções top-level
  // privadas para conseguirem ser usadas como `messageBuilder` em
  // `_ToolHelpEntry` (que é `const`).
  // ==========================================================================

  static String _postgresMessage(String tool) =>
      '$tool não encontrado no PATH do sistema.\n\n'
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

  static String _sqlServerMessage(String tool) =>
      'sqlcmd não encontrado no PATH do sistema.\n\n'
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

  static String _sybaseMessage(String tool) =>
      '$tool não encontrado no PATH do sistema.\n\n'
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

  static String _firebirdMessage(String tool) =>
      '$tool não encontrado no PATH do sistema.\n\n'
      'As ferramentas de linha de comando do Firebird não estão '
      'disponíveis.\n\n'
      'OPÇÕES PARA RESOLVER:\n\n'
      'Opção 1: Adicionar ao PATH manualmente\n'
      '  - Localize a pasta bin da instalação do Firebird\n'
      '    (ex.: C:\\Program Files\\Firebird\\Firebird_5_0\\)\n'
      '  - Adicione ao PATH do Windows:\n'
      '    * Pressione Win + X → "Sistema"\n'
      '    * Clique em "Configurações avançadas do sistema"\n'
      '    * Na aba "Avançado", clique em "Variáveis de Ambiente"\n'
      '    * Em "Variáveis do sistema", encontre "Path" e clique em '
      '"Editar"\n'
      '    * Clique em "Novo" e adicione o caminho completo da pasta '
      'bin\n'
      '    * Clique em "OK" em todas as janelas\n\n'
      'Opção 2: Instalar ou reparar o Firebird\n'
      '  - Baixe o instalador em https://firebirdsql.org/\n'
      '  - Marque a opção que adiciona as ferramentas ao PATH, se '
      'disponível\n\n'
      r'Consulte: docs\path_setup.md para mais detalhes.';
}

enum _ToolFamily { postgres, sqlServer, sybase, firebird }

class _ToolHelpEntry {
  const _ToolHelpEntry({
    required this.family,
    required this.knownTools,
    required this.defaultCanonicalName,
    required this.messageBuilder,
  });

  final _ToolFamily family;
  final Set<String> knownTools;
  final String defaultCanonicalName;
  final String Function(String canonicalToolName) messageBuilder;
}
