import 'dart:async';

import 'package:backup_database/application/providers/firebird_config_provider.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/tool_path_help.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/services/i_firebird_backup_service.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

/// **Organism** — Fluent dialog to create or edit a Firebird connection inside
/// [DatabaseConfigDialogShell]; includes connection test and tool-path hints.
class FirebirdConfigDialog extends StatefulWidget {
  const FirebirdConfigDialog({super.key, this.config});

  final FirebirdConfig? config;

  static Future<FirebirdConfig?> show(
    BuildContext context, {
    FirebirdConfig? config,
  }) async {
    return showDialog<FirebirdConfig>(
      context: context,
      builder: (BuildContext context) => FirebirdConfigDialog(config: config),
    );
  }

  @override
  State<FirebirdConfigDialog> createState() => _FirebirdConfigDialogState();
}

class _FirebirdConfigDialogState extends State<FirebirdConfigDialog> {
  static const int _kDefaultFirebirdPort = 3050;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _databaseFileController = TextEditingController();
  final TextEditingController _aliasController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '$_kDefaultFirebirdPort',
  );
  final TextEditingController _clientLibController = TextEditingController();
  final TextEditingController _cryptKeyController = TextEditingController();

  bool _isEnabled = true;
  bool _useEmbedded = false;
  FirebirdServerVersionHint _serverVersionHint = FirebirdServerVersionHint.auto;
  FirebirdServiceManagerMode _serviceManagerMode =
      FirebirdServiceManagerMode.auto;

  bool _isTestingConnection = false;

  late final String _configSessionId;
  late final IFirebirdBackupService _backupService;

  bool get _isEditing => widget.config != null;

  @override
  void initState() {
    super.initState();
    _configSessionId = widget.config?.id ?? const Uuid().v4();
    _backupService = getIt<IFirebirdBackupService>();
    if (widget.config != null) {
      final c = widget.config!;
      _nameController.text = c.name;
      _hostController.text = c.host;
      _databaseFileController.text = c.databaseFile;
      _aliasController.text = c.aliasName ?? '';
      _usernameController.text = c.username;
      _passwordController.text = c.password;
      _portController.text = c.portValue.toString();
      _clientLibController.text = c.clientLibraryPath ?? '';
      _cryptKeyController.text = c.cryptKey;
      _isEnabled = c.enabled;
      _useEmbedded = c.useEmbedded;
      _serverVersionHint = c.serverVersionHint;
      _serviceManagerMode = c.serviceManagerMode;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _databaseFileController.dispose();
    _aliasController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    _clientLibController.dispose();
    _cryptKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DatabaseConfigDialogShell(
      constraints: const BoxConstraints(
        minWidth: 600,
        maxWidth: 600,
        maxHeight: 800,
      ),
      title: Row(
        children: [
          const Icon(FluentIcons.server, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isEditing
                  ? appLocaleString(
                      context,
                      'Editar configuração Firebird',
                      'Edit Firebird configuration',
                    )
                  : appLocaleString(
                      context,
                      'Nova configuração Firebird',
                      'New Firebird configuration',
                    ),
              style: FluentTheme.of(context).typography.title,
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _nameController,
              label: appLocaleString(
                context,
                'Nome da configuração',
                'Configuration name',
              ),
              hint: 'Ex: Produção Firebird',
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return appLocaleString(
                    context,
                    'Nome é obrigatório',
                    'Name is required',
                  );
                }
                return null;
              },
              prefixIcon: const Icon(FluentIcons.tag),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: AppTextField(
                    controller: _hostController,
                    label: appLocaleString(context, 'Host', 'Host'),
                    hint: appLocaleString(
                      context,
                      'localhost ou IP',
                      'localhost or IP',
                    ),
                    validator: (String? value) {
                      if (!_useEmbedded &&
                          (value == null || value.trim().isEmpty)) {
                        return appLocaleString(
                          context,
                          'Host é obrigatório',
                          'Host is required',
                        );
                      }
                      return null;
                    },
                    prefixIcon: const Icon(FluentIcons.server),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: NumericField(
                    controller: _portController,
                    label: appLocaleString(context, 'Porta', 'Port'),
                    hint: '$_kDefaultFirebirdPort',
                    prefixIcon: FluentIcons.number_field,
                    minValue: 1,
                    maxValue: 65535,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _databaseFileController,
              label: appLocaleString(
                context,
                'Arquivo do banco (.fdb)',
                'Database file (.fdb)',
              ),
              hint: r'C:\Dados\minha_base.fdb',
              validator: (String? value) {
                final pathEmpty = value == null || value.trim().isEmpty;
                final aliasEmpty = _aliasController.text.trim().isEmpty;
                if (pathEmpty && aliasEmpty) {
                  return appLocaleString(
                    context,
                    'Informe o caminho do arquivo ou um alias',
                    'Enter the database file path or an alias',
                  );
                }
                return null;
              },
              prefixIcon: const Icon(FluentIcons.open_file),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _aliasController,
              label: appLocaleString(
                context,
                'Alias (opcional)',
                'Alias (optional)',
              ),
              hint: appLocaleString(
                context,
                'Nome lógico no databases.conf',
                'Logical name in databases.conf',
              ),
              prefixIcon: const Icon(FluentIcons.link),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _usernameController,
              label: appLocaleString(context, 'Usuario', 'Username'),
              hint: 'SYSDBA',
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return appLocaleString(
                    context,
                    'Usuário é obrigatório',
                    'Username is required',
                  );
                }
                return null;
              },
              prefixIcon: const Icon(FluentIcons.contact),
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _passwordController,
              hint: appLocaleString(
                context,
                'Senha do usuario',
                'User password',
              ),
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: appLocaleString(
                context,
                'Modo embedded',
                'Embedded mode',
              ),
              child: ToggleSwitch(
                checked: _useEmbedded,
                onChanged: (bool value) {
                  setState(() {
                    _useEmbedded = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _clientLibController,
              label: appLocaleString(
                context,
                'fbclient.dll (opcional)',
                'fbclient.dll (optional)',
              ),
              hint: appLocaleString(
                context,
                'Caminho completo se não estiver no PATH',
                'Full path if not on PATH',
              ),
              prefixIcon: const Icon(FluentIcons.folder),
            ),
            const SizedBox(height: 16),
            AppDropdown<FirebirdServerVersionHint>(
              label: appLocaleString(
                context,
                'Versão do servidor (dica)',
                'Server version (hint)',
              ),
              value: _serverVersionHint,
              items: FirebirdServerVersionHint.values
                  .map(
                    (FirebirdServerVersionHint v) =>
                        ComboBoxItem<FirebirdServerVersionHint>(
                          value: v,
                          child: Text(_firebirdVersionHintLabel(context, v)),
                        ),
                  )
                  .toList(growable: false),
              onChanged: (FirebirdServerVersionHint? value) {
                if (value != null) {
                  setState(() {
                    _serverVersionHint = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            AppDropdown<FirebirdServiceManagerMode>(
              label: appLocaleString(
                context,
                'Gerenciador de serviço',
                'Service manager',
              ),
              value: _serviceManagerMode,
              items: FirebirdServiceManagerMode.values
                  .map(
                    (FirebirdServiceManagerMode v) =>
                        ComboBoxItem<FirebirdServiceManagerMode>(
                          value: v,
                          child: Text(_serviceManagerModeLabel(context, v)),
                        ),
                  )
                  .toList(growable: false),
              onChanged: (FirebirdServiceManagerMode? value) {
                if (value != null) {
                  setState(() {
                    _serviceManagerMode = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _cryptKeyController,
              label: appLocaleString(
                context,
                'Chave de criptografia (opcional)',
                'Encryption key (optional)',
              ),
              hint: appLocaleString(
                context,
                'Somente se o banco usar crypt plugin',
                'Only if the database uses a crypt plugin',
              ),
              prefixIcon: const Icon(FluentIcons.lock),
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: appLocaleString(context, 'Habilitado', 'Enabled'),
              child: ToggleSwitch(
                checked: _isEnabled,
                onChanged: (bool value) {
                  setState(() {
                    _isEnabled = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appLocaleString(
                context,
                'Configuração ativa para uso em agendamentos',
                'Configuration active for schedules',
              ),
              style: FluentTheme.of(context).typography.caption,
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: appLocaleString(
                context,
                'Teste de conexão',
                'Connection test',
              ),
              child: Text(
                appLocaleString(
                  context,
                  'Usa gstat -h com as credenciais informadas (mesma base '
                      'usada pelo agendamento).',
                  'Uses gstat -h with the credentials entered (same probe '
                      'as scheduling).',
                ),
              ),
            ),
          ],
        ),
      ),
      dialogActions: [
        const CancelButton(),
        ActionButton(
          label: appLocaleString(context, 'Testar conexão', 'Test connection'),
          icon: FluentIcons.check_mark,
          onPressed: _testConnection,
          isLoading: _isTestingConnection,
        ),
        SaveButton(onPressed: _save, isEditing: _isEditing),
      ],
      onSubmitIntent: _save,
    );
  }

  Future<void> _testConnection() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    if (!mounted) {
      return;
    }

    try {
      var probeStarted = false;
      final mSuccess = appLocaleString(
        context,
        'Conexão testada com sucesso!',
        'Connection tested successfully!',
      );
      final mUnknownConn = appLocaleString(
        context,
        'Erro desconhecido ao testar conexão',
        'Unknown error testing connection',
      );
      final mErrTitle = appLocaleString(
        context,
        'Erro ao testar conexão',
        'Error testing connection',
      );
      final mUnknownShort = appLocaleString(
        context,
        'Erro desconhecido',
        'Unknown error',
      );
      final mListPrefix = appLocaleString(
        context,
        'Conexão OK, mas erro ao identificar a base: ',
        'Connection OK, but error resolving database identity: ',
      );

      final outcome =
          await TestConnectionRunner<FirebirdConfig>(
            validate: _validateFirebirdTestInputs,
            buildConfig: _buildFirebirdTestConfig,
            runTest: (FirebirdConfig config) async {
              final probeResult = await _backupService
                  .probeGstatHeaderConnection(
                    config,
                  );
              if (probeResult.isError()) {
                final failure = probeResult.exceptionOrNull()!;
                var msg = testConnectionUserMessage(
                  failure,
                  fallback: mUnknownConn,
                );
                final lower = msg.toLowerCase();
                if (ToolPathHelp.isToolNotFoundError(lower, 'gstat')) {
                  msg = ToolPathHelp.buildMessage('gstat');
                }
                return TestConnectionFailed(msg);
              }
              final data = probeResult.getOrNull()!;
              final hint = data.versionHint;
              final listResult = await _backupService.listDatabases(
                config: config,
              );
              final names = listResult.getOrNull();
              if (names != null) {
                return TestConnectionSucceeded(
                  versionHint: hint.isEmpty ? null : hint,
                  databases: names,
                );
              }
              final listFailure = listResult.exceptionOrNull();
              final detail = testConnectionUserMessage(
                listFailure,
                fallback: mUnknownShort,
              );
              return TestConnectionSucceeded(
                versionHint: hint.isEmpty ? null : hint,
                listWarning: '$mListPrefix$detail',
              );
            },
          ).execute(
            afterValidation: () {
              if (!mounted) {
                return;
              }
              setState(() {
                _isTestingConnection = true;
              });
            },
            onProbeStarted: () {
              probeStarted = true;
            },
          );
      if (!mounted) {
        return;
      }
      if (probeStarted) {
        context.read<FirebirdConfigProvider>().recordConnectionTest(
          _configSessionId,
          success: outcome is TestConnectionSucceeded,
        );
      }
      switch (outcome) {
        case TestConnectionSucceeded(
          :final versionHint,
          :final databases,
          :final listWarning,
        ):
          if (listWarning != null) {
            unawaited(
              FluentInfoBarFeedback.showWarning(
                context,
                message: listWarning,
              ),
            );
            break;
          }
          final dbExtra = databases.isEmpty
              ? ''
              : appLocaleString(
                  context,
                  ' Base: ${databases.first}',
                  ' Database: ${databases.first}',
                );
          final extra = versionHint == null || versionHint.trim().isEmpty
              ? ''
              : appLocaleString(
                  context,
                  ' Versao detectada: $versionHint',
                  ' Detected version: $versionHint',
                );
          unawaited(
            FluentInfoBarFeedback.showSuccess(
              context,
              message: '$mSuccess$dbExtra$extra',
            ),
          );
        case TestConnectionFailed(:final message):
          final rawMessage = message.isNotEmpty ? message : mUnknownConn;
          unawaited(
            MessageModal.showError(
              context,
              title: mErrTitle,
              message: rawMessage,
            ),
          );
      }
    } on Object catch (e, stackTrace) {
      if (!mounted) {
        return;
      }

      LoggerService.error('Erro ao testar conexao Firebird', e, stackTrace);

      final errorMessage = e.toString().replaceAll('Exception: ', '');

      unawaited(
        MessageModal.showError(
          context,
          title: appLocaleString(
            context,
            'Erro ao testar conexão',
            'Error testing connection',
          ),
          message: errorMessage.isNotEmpty
              ? errorMessage
              : appLocaleString(context, 'Erro desconhecido', 'Unknown error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTestingConnection = false;
        });
      }
    }
  }

  String? _validateFirebirdTestInputs() {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      return appLocaleString(
        context,
        'Porta invalida. Deve estar entre 1 e 65535.',
        'Invalid port. Must be between 1 and 65535.',
      );
    }
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      return appLocaleString(
        context,
        'Preencha usuario e senha para testar',
        'Fill username and password to test',
      );
    }
    final path = _databaseFileController.text.trim();
    final alias = _aliasController.text.trim();
    if (path.isEmpty && alias.isEmpty) {
      return appLocaleString(
        context,
        'Informe o caminho do banco no servidor ou um alias para testar',
        'Enter the server database path or an alias to test',
      );
    }
    if (!_useEmbedded && _hostController.text.trim().isEmpty) {
      return appLocaleString(
        context,
        'Preencha o host para testar (modo cliente/servidor)',
        'Fill in the host to test (client/server mode)',
      );
    }
    return null;
  }

  FirebirdConfig _buildFirebirdTestConfig() {
    final portParsed = int.tryParse(_portController.text.trim())!;
    final aliasTrimmed = _aliasController.text.trim();
    final aliasName = aliasTrimmed.isEmpty ? null : aliasTrimmed;
    final clientLibTrimmed = _clientLibController.text.trim();
    final clientLibraryPath = clientLibTrimmed.isEmpty
        ? null
        : clientLibTrimmed;
    return FirebirdConfig(
      id: _configSessionId,
      name: 'temp',
      host: _hostController.text.trim(),
      databaseFile: _databaseFileController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      port: PortNumber(portParsed),
      aliasName: aliasName,
      useEmbedded: _useEmbedded,
      clientLibraryPath: clientLibraryPath,
      serverVersionHint: _serverVersionHint,
      serviceManagerMode: _serviceManagerMode,
      cryptKey: _cryptKeyController.text,
    );
  }

  String _firebirdVersionHintLabel(
    BuildContext context,
    FirebirdServerVersionHint v,
  ) {
    return switch (v) {
      FirebirdServerVersionHint.auto => appLocaleString(
        context,
        'Automático',
        'Automatic',
      ),
      FirebirdServerVersionHint.v25 => 'Firebird 2.5',
      FirebirdServerVersionHint.v30 => 'Firebird 3.0',
      FirebirdServerVersionHint.v40 => 'Firebird 4.0',
    };
  }

  String _serviceManagerModeLabel(
    BuildContext context,
    FirebirdServiceManagerMode v,
  ) {
    return switch (v) {
      FirebirdServiceManagerMode.auto => appLocaleString(
        context,
        'Automático',
        'Automatic',
      ),
      FirebirdServiceManagerMode.always => appLocaleString(
        context,
        'Sempre usar',
        'Always use',
      ),
      FirebirdServiceManagerMode.never => appLocaleString(
        context,
        'Nunca usar',
        'Never use',
      ),
    };
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final portParsed = int.tryParse(_portController.text.trim());
    if (portParsed == null || portParsed < 1 || portParsed > 65535) {
      unawaited(
        MessageModal.showError(
          context,
          message: appLocaleString(
            context,
            'Porta invalida. Deve estar entre 1 e 65535.',
            'Invalid port. Must be between 1 and 65535.',
          ),
        ),
      );
      return;
    }

    if (!_useEmbedded && _hostController.text.trim().isEmpty) {
      unawaited(
        MessageModal.showError(
          context,
          message: appLocaleString(
            context,
            'Host e obrigatorio no modo cliente/servidor.',
            'Host is required in client/server mode.',
          ),
        ),
      );
      return;
    }

    final aliasTrimmed = _aliasController.text.trim();
    final aliasName = aliasTrimmed.isEmpty ? null : aliasTrimmed;

    final clientLibTrimmed = _clientLibController.text.trim();
    final clientLibraryPath = clientLibTrimmed.isEmpty
        ? null
        : clientLibTrimmed;

    final firebirdConfig = FirebirdConfig(
      id: _configSessionId,
      name: _nameController.text.trim(),
      host: _hostController.text.trim(),
      databaseFile: _databaseFileController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      port: PortNumber(portParsed),
      aliasName: aliasName,
      useEmbedded: _useEmbedded,
      clientLibraryPath: clientLibraryPath,
      serverVersionHint: _serverVersionHint,
      serviceManagerMode: _serviceManagerMode,
      cryptKey: _cryptKeyController.text,
      enabled: _isEnabled,
      createdAt: widget.config?.createdAt,
      updatedAt: widget.config?.updatedAt,
    );
    Navigator.of(context).pop(firebirdConfig);
  }
}
