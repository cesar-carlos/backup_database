import 'dart:async';

import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

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

  bool get _isEditing => widget.config != null;

  @override
  void initState() {
    super.initState();
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
                      if (value == null || value.trim().isEmpty) {
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
                if (value == null || value.trim().isEmpty) {
                  return appLocaleString(
                    context,
                    'Caminho do arquivo é obrigatório',
                    'Database file path is required',
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
            InfoBar(
              title: Text(
                appLocaleString(context, 'Teste de conexão', 'Connection test'),
              ),
              content: Text(
                appLocaleString(
                  context,
                  'O teste de conexão será habilitado quando o motor de '
                      'backup Firebird (gbak) estiver integrado.',
                  'Connection testing will be available once the Firebird '
                      'backup engine (gbak) is integrated.',
                ),
              ),
            ),
          ],
        ),
      ),
      dialogActions: [
        const CancelButton(),
        SaveButton(onPressed: _save, isEditing: _isEditing),
      ],
      onSubmitIntent: _save,
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

    final aliasTrimmed = _aliasController.text.trim();
    final aliasName = aliasTrimmed.isEmpty ? null : aliasTrimmed;

    final clientLibTrimmed = _clientLibController.text.trim();
    final clientLibraryPath = clientLibTrimmed.isEmpty
        ? null
        : clientLibTrimmed;

    final firebirdConfig = FirebirdConfig(
      id: widget.config?.id,
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
