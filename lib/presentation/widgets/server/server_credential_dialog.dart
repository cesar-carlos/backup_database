import 'dart:math';

import 'package:backup_database/domain/entities/server_credential.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/server/server_credential_form_result.dart';
import 'package:fluent_ui/fluent_ui.dart';

const int _minPasswordLength = 8;

class ServerCredentialDialog extends StatefulWidget {
  const ServerCredentialDialog({super.key, this.credential});
  final ServerCredential? credential;

  static Future<ServerCredentialFormResult?> show(
    BuildContext context, {
    ServerCredential? credential,
  }) {
    return showDialog<ServerCredentialFormResult>(
      context: context,
      builder: (context) => ServerCredentialDialog(credential: credential),
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
    }
  }

  @override
  void dispose() {
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
    return List.generate(_minPasswordLength + 4, (_) => chars[r.nextInt(chars.length)]).join();
  }

  void _fillGeneratedPassword() {
    final pwd = _generatePassword();
    _passwordController.text = pwd;
    _confirmPasswordController.text = pwd;
    setState(() {});
  }

  String? _validatePassword(String? value) {
    if (_isEditing && (value == null || value.isEmpty)) return null;
    if (value == null || value.isEmpty) return 'Senha é obrigatória';
    if (value.length < _minPasswordLength) {
      return 'Senha deve ter pelo menos $_minPasswordLength caracteres';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if (_isEditing && _passwordController.text.isEmpty && (value == null || value.isEmpty)) {
      return null;
    }
    if (value != _passwordController.text) return 'As senhas não coincidem';
    return null;
  }

  void _submit() {
    final serverId = _serverIdController.text.trim();
    final name = _nameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (serverId.isEmpty) {
      MessageModal.showError(context, message: 'Informe o Server ID.');
      return;
    }
    if (name.isEmpty) {
      MessageModal.showError(context, message: 'Informe um nome para a credencial.');
      return;
    }
    if (!_isEditing) {
      if (password.isEmpty) {
        MessageModal.showError(context, message: 'Informe a senha.');
        return;
      }
      if (password.length < _minPasswordLength) {
        MessageModal.showError(
          context,
          message: 'A senha deve ter pelo menos $_minPasswordLength caracteres.',
        );
        return;
      }
    } else if (password.isNotEmpty && password.length < _minPasswordLength) {
      MessageModal.showError(
        context,
        message: 'A senha deve ter pelo menos $_minPasswordLength caracteres.',
      );
      return;
    }
    if (password != confirm) {
      MessageModal.showError(context, message: 'As senhas não coincidem.');
      return;
    }

    Navigator.of(context).pop(ServerCredentialFormResult(
      serverId: serverId,
      name: name,
      plainPassword: password.isEmpty ? null : password,
      isActive: _isActive,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text(_isEditing ? 'Editar Credencial' : 'Nova Credencial'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoLabel(
                label: 'Server ID',
                child: TextBox(
                  controller: _serverIdController,
                  placeholder: 'Identificador único do servidor',
                  enabled: !_isEditing,
                ),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: 'Nome',
                child: TextBox(
                  controller: _nameController,
                  placeholder: 'Nome descritivo',
                ),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _passwordController,
                hint: _isEditing ? 'Deixe em branco para manter' : 'Mínimo $_minPasswordLength caracteres',
                validator: _validatePassword,
              ),
              const SizedBox(height: 16),
              PasswordField(
                label: 'Confirmar senha',
                controller: _confirmPasswordController,
                hint: _isEditing ? 'Deixe em branco para manter' : 'Repita a senha',
                validator: _validateConfirm,
              ),
              const SizedBox(height: 16),
              Button(
                onPressed: _fillGeneratedPassword,
                child: const Text('Gerar senha aleatória'),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: 'Descrição (opcional)',
                child: TextBox(
                  controller: _descriptionController,
                  placeholder: 'Observações',
                  maxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: 'Ativo',
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
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
