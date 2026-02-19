import 'dart:math';

import 'package:backup_database/domain/entities/server_credential.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/server/server_credential_form_result.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

const int _minPasswordLength = 8;
const int _serverIdLength = 8;

class ServerCredentialDialog extends StatefulWidget {
  const ServerCredentialDialog({
    super.key,
    this.credential,
    this.existingPassword,
  });
  final ServerCredential? credential;
  final String? existingPassword;

  static Future<ServerCredentialFormResult?> show(
    BuildContext context, {
    ServerCredential? credential,
    String? existingPassword,
  }) {
    return showDialog<ServerCredentialFormResult>(
      context: context,
      builder: (context) => ServerCredentialDialog(
        credential: credential,
        existingPassword: existingPassword,
      ),
    );
  }

  @override
  State<ServerCredentialDialog> createState() => _ServerCredentialDialogState();
}

class _ServerCredentialDialogState extends State<ServerCredentialDialog> {
  final _serverIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isActive = true;
  bool _isEditing = false;

  String _t(String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  @override
  void initState() {
    super.initState();
    _isEditing = widget.credential != null;
    if (widget.credential != null) {
      final c = widget.credential!;
      _serverIdController.text = c.serverId;
      _nameController.text = c.name;
      _isActive = c.isActive;
      _descriptionController.text = c.description ?? '';
      if (widget.existingPassword != null &&
          widget.existingPassword!.isNotEmpty) {
        _passwordController.text = widget.existingPassword!;
        _confirmPasswordController.text = widget.existingPassword!;
      }
    } else {
      _serverIdController.text = _generateServerId();
    }
    _passwordController.addListener(_onPasswordChanged);
  }

  String _generateServerId() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(
      _serverIdLength,
      (_) => chars[r.nextInt(chars.length)],
    ).join();
  }

  void _onPasswordChanged() => setState(() {});

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _serverIdController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _generatePassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%';
    final r = Random.secure();
    return List.generate(
      _minPasswordLength + 4,
      (_) => chars[r.nextInt(chars.length)],
    ).join();
  }

  void _fillGeneratedPassword() {
    final pwd = _generatePassword();
    _passwordController.text = pwd;
    _confirmPasswordController.text = pwd;
    setState(() {});
  }

  String? _validatePassword(String? value) {
    if (_isEditing && (value == null || value.isEmpty)) return null;
    if (value == null || value.isEmpty) {
      return _t('Senha e obrigatoria', 'Password is required');
    }
    if (value.length < _minPasswordLength) {
      return _t(
        'Senha deve ter pelo menos $_minPasswordLength caracteres',
        'Password must have at least $_minPasswordLength characters',
      );
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if (_isEditing &&
        _passwordController.text.isEmpty &&
        (value == null || value.isEmpty)) {
      return null;
    }
    if (value != _passwordController.text) {
      return _t('As senhas nao coincidem', 'Passwords do not match');
    }
    return null;
  }

  void _submit() {
    final serverId = _serverIdController.text.trim();
    final name = _nameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (serverId.isEmpty) {
      MessageModal.showError(
        context,
        message: _t('Informe o Server ID.', 'Enter Server ID.'),
      );
      return;
    }
    if (name.isEmpty) {
      MessageModal.showError(
        context,
        message: _t(
          'Informe um nome para a credencial.',
          'Enter a name for the credential.',
        ),
      );
      return;
    }
    if (!_isEditing) {
      if (password.isEmpty) {
        MessageModal.showError(
          context,
          message: _t('Informe a senha.', 'Enter password.'),
        );
        return;
      }
      if (password.length < _minPasswordLength) {
        MessageModal.showError(
          context,
          message: _t(
            'A senha deve ter pelo menos $_minPasswordLength caracteres.',
            'Password must have at least $_minPasswordLength characters.',
          ),
        );
        return;
      }
    } else if (password.isNotEmpty && password.length < _minPasswordLength) {
      MessageModal.showError(
        context,
        message: _t(
          'A senha deve ter pelo menos $_minPasswordLength caracteres.',
          'Password must have at least $_minPasswordLength characters.',
        ),
      );
      return;
    }
    if (password != confirm) {
      MessageModal.showError(
        context,
        message: _t('As senhas nao coincidem.', 'Passwords do not match.'),
      );
      return;
    }

    Navigator.of(context).pop(
      ServerCredentialFormResult(
        serverId: serverId,
        name: name,
        plainPassword: password.isEmpty ? null : password,
        isActive: _isActive,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text(
        _isEditing
            ? _t('Editar credencial', 'Edit credential')
            : _t('Nova credencial', 'New credential'),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoLabel(
                label: _t('ID do servidor', 'Server ID'),
                child: Row(
                  children: [
                    Expanded(
                      child: TextBox(
                        controller: _serverIdController,
                        placeholder: _t(
                          'Identificador unico do servidor',
                          'Unique server identifier',
                        ),
                        enabled: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: _t('Copiar Server ID', 'Copy Server ID'),
                      child: IconButton(
                        icon: const Icon(FluentIcons.copy),
                        onPressed: () {
                          final text = _serverIdController.text.trim();
                          if (text.isNotEmpty) {
                            Clipboard.setData(ClipboardData(text: text));
                            MessageModal.showInfo(
                              context,
                              message: _t(
                                'Server ID copiado para a area de transferencia.',
                                'Server ID copied to clipboard.',
                              ),
                              title: _t('Copiado', 'Copied'),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: _t('Nome', 'Name'),
                child: TextBox(
                  controller: _nameController,
                  placeholder: _t('Nome descritivo', 'Descriptive name'),
                ),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _passwordController,
                hint: _isEditing
                    ? _t('Deixe em branco para manter', 'Leave blank to keep')
                    : _t(
                        'Minimo $_minPasswordLength caracteres',
                        'Minimum $_minPasswordLength characters',
                      ),
                validator: _validatePassword,
              ),
              if (_isEditing && _passwordController.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Tooltip(
                      message: _t(
                        'Copiar senha para a area de transferencia',
                        'Copy password to clipboard',
                      ),
                      child: Button(
                        onPressed: () {
                          final text = _passwordController.text;
                          if (text.isNotEmpty) {
                            Clipboard.setData(ClipboardData(text: text));
                            MessageModal.showInfo(
                              context,
                              message: _t(
                                'Senha copiada para a area de transferencia.',
                                'Password copied to clipboard.',
                              ),
                              title: _t('Copiado', 'Copied'),
                            );
                          }
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FluentIcons.copy, size: 16),
                            const SizedBox(width: 8),
                            Text(_t('Copiar senha', 'Copy password')),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              PasswordField(
                label: _t('Confirmar senha', 'Confirm password'),
                controller: _confirmPasswordController,
                hint: _isEditing
                    ? _t('Deixe em branco para manter', 'Leave blank to keep')
                    : _t('Repita a senha', 'Repeat password'),
                validator: _validateConfirm,
              ),
              const SizedBox(height: 16),
              Button(
                onPressed: _fillGeneratedPassword,
                child: Text(
                  _t('Gerar senha aleatoria', 'Generate random password'),
                ),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: _t('Descricao (opcional)', 'Description (optional)'),
                child: TextBox(
                  controller: _descriptionController,
                  placeholder: _t('Observacoes', 'Notes'),
                  maxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: _t('Ativo', 'Active'),
                child: ToggleSwitch(
                  checked: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t('Cancelar', 'Cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_t('Salvar', 'Save')),
        ),
      ],
    );
  }
}
