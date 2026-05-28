import 'dart:async';

import 'package:backup_database/application/providers/remote_database_config_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:uuid/uuid.dart';

/// **Organism** — formulário modal para **criar** ou **atualizar** uma
/// configuração de banco no servidor remoto.
///
/// §audit-2026-05-28 wave 3 (P2): o `ConnectionManager` já tinha os
/// RPCs `createRemoteDatabaseConfig` / `updateRemoteDatabaseConfig`
/// desde a wave 1, mas faltava UI — operador só conseguia list / test
/// / delete via tela, e create/update viravam tarefa de administração
/// manual no servidor. Esta dialog dá feature parity com os dialogs
/// locais de SGBD sem duplicar validação por tipo (o servidor é a
/// autoridade do schema concreto).
/// Modo do [RemoteDatabaseConfigEditDialog] — exposto público porque
/// faz parte do contrato do construtor `.create` / `.edit`.
enum RemoteDatabaseConfigEditMode { create, edit }

class RemoteDatabaseConfigEditDialog extends StatefulWidget {
  const RemoteDatabaseConfigEditDialog._({
    required this.provider,
    required this.databaseType,
    required this.mode,
    this.initial,
    this.editingConfigId,
    super.key,
  });

  /// Modo "novo registro" — formulário em branco. O caller escolhe
  /// o `databaseType` via picker antes de abrir.
  factory RemoteDatabaseConfigEditDialog.create({
    required RemoteDatabaseConfigProvider provider,
    required RemoteDatabaseType databaseType,
    Key? key,
  }) {
    return RemoteDatabaseConfigEditDialog._(
      provider: provider,
      databaseType: databaseType,
      mode: RemoteDatabaseConfigEditMode.create,
      key: key,
    );
  }

  /// Modo "edição" — formulário pré-preenchido com os campos
  /// devolvidos pelo servidor (`listRemoteDatabaseConfigs`).
  factory RemoteDatabaseConfigEditDialog.edit({
    required RemoteDatabaseConfigProvider provider,
    required RemoteDatabaseType databaseType,
    required String configId,
    required Map<String, dynamic> initial,
    Key? key,
  }) {
    return RemoteDatabaseConfigEditDialog._(
      provider: provider,
      databaseType: databaseType,
      mode: RemoteDatabaseConfigEditMode.edit,
      initial: initial,
      editingConfigId: configId,
      key: key,
    );
  }

  static Future<bool?> show(
    BuildContext context, {
    required RemoteDatabaseConfigProvider provider,
    required RemoteDatabaseType databaseType,
    String? editingConfigId,
    Map<String, dynamic>? initial,
  }) {
    final isEdit = editingConfigId != null && initial != null;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => isEdit
          ? RemoteDatabaseConfigEditDialog.edit(
              provider: provider,
              databaseType: databaseType,
              configId: editingConfigId,
              initial: initial,
            )
          : RemoteDatabaseConfigEditDialog.create(
              provider: provider,
              databaseType: databaseType,
            ),
    );
  }

  final RemoteDatabaseConfigProvider provider;
  final RemoteDatabaseType databaseType;
  final RemoteDatabaseConfigEditMode mode;
  final Map<String, dynamic>? initial;
  final String? editingConfigId;

  @override
  State<RemoteDatabaseConfigEditDialog> createState() =>
      _RemoteDatabaseConfigEditDialogState();
}

class _RemoteDatabaseConfigEditDialogState
    extends State<RemoteDatabaseConfigEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _databaseCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _cryptKeyCtrl;
  late final TextEditingController _backupFolderCtrl;
  bool _saving = false;
  String? _errorMessage;

  bool get _isFirebird => widget.databaseType == RemoteDatabaseType.firebird;
  bool get _isEdit => widget.mode == RemoteDatabaseConfigEditMode.edit;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? const <String, dynamic>{};
    _nameCtrl = TextEditingController(
      text: _stringFromInitial(initial, 'name'),
    );
    _hostCtrl = TextEditingController(
      text: _stringFromInitial(initial, 'host'),
    );
    _portCtrl = TextEditingController(
      text: _stringFromInitial(
        initial,
        'port',
        fallback: _defaultPortFor(widget.databaseType).toString(),
      ),
    );
    _databaseCtrl = TextEditingController(
      text: _stringFromInitial(initial, 'database'),
    );
    _usernameCtrl = TextEditingController(
      text: _stringFromInitial(initial, 'username'),
    );
    _passwordCtrl = TextEditingController();
    _cryptKeyCtrl = TextEditingController();
    _backupFolderCtrl = TextEditingController(
      text: _stringFromInitial(initial, 'backupFolder'),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _databaseCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _cryptKeyCtrl.dispose();
    _backupFolderCtrl.dispose();
    super.dispose();
  }

  String _stringFromInitial(
    Map<String, dynamic> map,
    String key, {
    String fallback = '',
  }) {
    final v = map[key];
    if (v == null) return fallback;
    if (v is String) return v;
    return v.toString();
  }

  int _defaultPortFor(RemoteDatabaseType type) => switch (type) {
    RemoteDatabaseType.sqlServer => 1433,
    RemoteDatabaseType.postgres => 5432,
    RemoteDatabaseType.sybase => 5000,
    RemoteDatabaseType.firebird => 3050,
  };

  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) {
      return appLocaleString(
        context,
        'Nome é obrigatório.',
        'Name is required.',
      );
    }
    if (_hostCtrl.text.trim().isEmpty) {
      return appLocaleString(
        context,
        'Host é obrigatório.',
        'Host is required.',
      );
    }
    final port = int.tryParse(_portCtrl.text.trim());
    if (port == null || port <= 0 || port > 65535) {
      return appLocaleString(
        context,
        'Porta deve ser um número entre 1 e 65535.',
        'Port must be a number between 1 and 65535.',
      );
    }
    if (_databaseCtrl.text.trim().isEmpty) {
      return appLocaleString(
        context,
        'Nome do banco é obrigatório.',
        'Database name is required.',
      );
    }
    if (_usernameCtrl.text.trim().isEmpty) {
      return appLocaleString(
        context,
        'Usuário é obrigatório.',
        'Username is required.',
      );
    }
    if (!_isEdit && _passwordCtrl.text.isEmpty) {
      // Em edição, senha vazia significa "manter a atual"; em criação
      // exigimos algum valor.
      return appLocaleString(
        context,
        'Senha é obrigatória ao criar um banco novo.',
        'Password is required when creating a new database.',
      );
    }
    return null;
  }

  Map<String, dynamic> _buildPayload() {
    final payload = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'host': _hostCtrl.text.trim(),
      'port': int.parse(_portCtrl.text.trim()),
      'database': _databaseCtrl.text.trim(),
      'username': _usernameCtrl.text.trim(),
      // Senha só vai no payload se o usuário digitou algo (na edição,
      // string vazia = manter atual).
      if (_passwordCtrl.text.isNotEmpty) 'password': _passwordCtrl.text,
      if (_isFirebird && _cryptKeyCtrl.text.isNotEmpty)
        'cryptKey': _cryptKeyCtrl.text,
      if (_backupFolderCtrl.text.trim().isNotEmpty)
        'backupFolder': _backupFolderCtrl.text.trim(),
    };
    if (_isEdit) {
      payload['id'] = widget.editingConfigId;
    }
    return payload;
  }

  Future<void> _onSubmit() async {
    final validation = _validate();
    if (validation != null) {
      setState(() => _errorMessage = validation);
      return;
    }
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    final payload = _buildPayload();
    final idempotencyKey = const Uuid().v4();
    final errorMessage = _isEdit
        ? await widget.provider.updateConfig(
            databaseType: widget.databaseType,
            config: payload,
            idempotencyKey: idempotencyKey,
          )
        : await widget.provider.createConfig(
            databaseType: widget.databaseType,
            config: payload,
            idempotencyKey: idempotencyKey,
          );
    if (!mounted) return;
    if (errorMessage != null) {
      setState(() {
        _saving = false;
        _errorMessage = errorMessage;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = remoteDatabaseTypeLabel(widget.databaseType);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 560),
      title: Text(
        _isEdit
            ? appLocaleString(
                context,
                'Editar banco remoto ($typeLabel)',
                'Edit remote database ($typeLabel)',
              )
            : appLocaleString(
                context,
                'Novo banco remoto ($typeLabel)',
                'New remote database ($typeLabel)',
              ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LabeledField(
              label: appLocaleString(context, 'Nome', 'Name'),
              controller: _nameCtrl,
              enabled: !_saving,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _LabeledField(
                    label: appLocaleString(context, 'Host', 'Host'),
                    controller: _hostCtrl,
                    enabled: !_saving,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _LabeledField(
                    label: appLocaleString(context, 'Porta', 'Port'),
                    controller: _portCtrl,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _LabeledField(
              label: appLocaleString(context, 'Banco / Database', 'Database'),
              controller: _databaseCtrl,
              enabled: !_saving,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _LabeledField(
                    label: appLocaleString(context, 'Usuário', 'Username'),
                    controller: _usernameCtrl,
                    enabled: !_saving,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _LabeledField(
                    label: _isEdit
                        ? appLocaleString(
                            context,
                            'Senha (vazio = manter)',
                            'Password (empty = keep)',
                          )
                        : appLocaleString(context, 'Senha', 'Password'),
                    controller: _passwordCtrl,
                    enabled: !_saving,
                    obscureText: true,
                  ),
                ),
              ],
            ),
            if (_isFirebird) ...[
              const SizedBox(height: AppSpacing.sm),
              _LabeledField(
                label: _isEdit
                    ? appLocaleString(
                        context,
                        'Crypt key (vazio = manter)',
                        'Crypt key (empty = keep)',
                      )
                    : appLocaleString(
                        context,
                        'Crypt key (opcional)',
                        'Crypt key (optional)',
                      ),
                controller: _cryptKeyCtrl,
                enabled: !_saving,
                obscureText: true,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            _LabeledField(
              label: appLocaleString(
                context,
                'Pasta de backup (servidor) — opcional',
                'Backup folder (server) — optional',
              ),
              controller: _backupFolderCtrl,
              enabled: !_saving,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SelectableText.rich(
                TextSpan(
                  text: appLocaleString(context, 'Erro: ', 'Error: '),
                  style: FluentTheme.of(context).typography.body?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: context.colors.danger,
                  ),
                  children: [
                    TextSpan(
                      text: _errorMessage,
                      style: TextStyle(
                        color: context.colors.danger,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(appLocaleString(context, 'Cancelar', 'Cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _onSubmit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : Text(
                  _isEdit
                      ? appLocaleString(context, 'Salvar', 'Save')
                      : appLocaleString(context, 'Criar', 'Create'),
                ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FluentTheme.of(context).typography.body),
        const SizedBox(height: AppSpacing.xs),
        TextBox(
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
        ),
      ],
    );
  }
}
