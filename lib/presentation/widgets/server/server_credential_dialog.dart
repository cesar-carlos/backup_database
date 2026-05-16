import 'dart:async';
import 'dart:math';

import 'package:backup_database/core/l10n/app_locale_string.dart';
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
      return appLocaleString(
        context,
        'Senha é obrigatória',
        'Password is required',
      );
    }
    if (value.length < _minPasswordLength) {
      return appLocaleString(
        context,
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
      return appLocaleString(
        context,
        'As senhas não coincidem',
        'Passwords do not match',
      );
    }
    return null;
  }

  void _submit() {
    final serverId = _serverIdController.text.trim();
    final name = _nameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (serverId.isEmpty) {
      unawaited(MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'Informe o Server ID.',
          'Enter Server ID.',
        ),
      ));
      return;
    }
    if (name.isEmpty) {
      unawaited(MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'Informe um nome para a credencial.',
          'Enter a name for the credential.',
        ),
      ));
      return;
    }
    if (!_isEditing) {
      if (password.isEmpty) {
        unawaited(MessageModal.showError(
          context,
          message: appLocaleString(
            context,
            'Informe a senha.',
            'Enter password.',
          ),
        ));
        return;
      }
      if (password.length < _minPasswordLength) {
        unawaited(MessageModal.showError(
          context,
          message: appLocaleString(
            context,
            'A senha deve ter pelo menos $_minPasswordLength caracteres.',
            'Password must have at least $_minPasswordLength characters.',
          ),
        ));
        return;
      }
    } else if (password.isNotEmpty && password.length < _minPasswordLength) {
      unawaited(MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'A senha deve ter pelo menos $_minPasswordLength caracteres.',
          'Password must have at least $_minPasswordLength characters.',
        ),
      ));
      return;
    }
    if (password != confirm) {
      unawaited(MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'As senhas não coincidem.',
          'Passwords do not match.',
        ),
      ));
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
            ? appLocaleString(context, 'Editar credencial', 'Edit credential')
            : appLocaleString(context, 'Nova credencial', 'New credential'),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoLabel(
                label: appLocaleString(context, 'ID do servidor', 'Server ID'),
                child: Row(
                  children: [
                    Expanded(
                      child: TextBox(
                        controller: _serverIdController,
                        placeholder: appLocaleString(
                          context,
                          'Identificador unico do servidor',
                          'Unique server identifier',
                        ),
                        enabled: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: appLocaleString(
                        context,
                        'Copiar Server ID',
                        'Copy Server ID',
                      ),
                      child: IconButton(
                        icon: const Icon(FluentIcons.copy),
                        onPressed: () {
                          final text = _serverIdController.text.trim();
                          if (text.isNotEmpty) {
                            unawaited(
                              Clipboard.setData(ClipboardData(text: text)),
                            );
                            unawaited(
                              MessageModal.showInfo(
                                context,
                                message: appLocaleString(
                                  context,
                                  'Server ID copiado para a area de transferencia.',
                                  'Server ID copied to clipboard.',
                                ),
                                title: appLocaleString(
                                  context,
                                  'Copiado',
                                  'Copied',
                                ),
                              ),
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
                label: appLocaleString(context, 'Nome', 'Name'),
                child: TextBox(
                  controller: _nameController,
                  placeholder: appLocaleString(
                    context,
                    'Nome descritivo',
                    'Descriptive name',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _passwordController,
                hint: _isEditing
                    ? appLocaleString(
                        context,
                        'Deixe em branco para manter',
                        'Leave blank to keep',
                      )
                    : appLocaleString(
                        context,
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
                      message: appLocaleString(
                        context,
                        'Copiar senha para a area de transferencia',
                        'Copy password to clipboard',
                      ),
                      child: Button(
                        onPressed: () {
                          final text = _passwordController.text;
                          if (text.isNotEmpty) {
                            unawaited(
                              Clipboard.setData(ClipboardData(text: text)),
                            );
                            unawaited(
                              MessageModal.showInfo(
                                context,
                                message: appLocaleString(
                                  context,
                                  'Senha copiada para a area de transferencia.',
                                  'Password copied to clipboard.',
                                ),
                                title: appLocaleString(
                                  context,
                                  'Copiado',
                                  'Copied',
                                ),
                              ),
                            );
                          }
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FluentIcons.copy, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              appLocaleString(
                                context,
                                'Copiar senha',
                                'Copy password',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              PasswordField(
                label: appLocaleString(
                  context,
                  'Confirmar senha',
                  'Confirm password',
                ),
                controller: _confirmPasswordController,
                hint: _isEditing
                    ? appLocaleString(
                        context,
                        'Deixe em branco para manter',
                        'Leave blank to keep',
                      )
                    : appLocaleString(
                        context,
                        'Repita a senha',
                        'Repeat password',
                      ),
                validator: _validateConfirm,
              ),
              const SizedBox(height: 16),
              Button(
                onPressed: _fillGeneratedPassword,
                child: Text(
                  appLocaleString(
                    context,
                    'Gerar senha aleatoria',
                    'Generate random password',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: appLocaleString(
                  context,
                  'Descrição (opcional)',
                  'Description (optional)',
                ),
                child: TextBox(
                  controller: _descriptionController,
                  placeholder: appLocaleString(context, 'Observações', 'Notes'),
                  maxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: appLocaleString(context, 'Ativo', 'Active'),
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
          child: Text(appLocaleString(context, 'Cancelar', 'Cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(appLocaleString(context, 'Salvar', 'Save')),
        ),
      ],
    );
  }
}
