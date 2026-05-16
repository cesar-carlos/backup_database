import 'dart:async';

import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/presentation/widgets/client/connection_form_result.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({super.key, this.connection});
  final ServerConnection? connection;

  static Future<ConnectionFormResult?> show(
    BuildContext context, {
    ServerConnection? connection,
  }) {
    return showDialog<ConnectionFormResult>(
      context: context,
      builder: (context) => ConnectionDialog(connection: connection),
    );
  }

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final _nameController = TextEditingController();
  final _serverIdController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '9527');
  final _passwordController = TextEditingController();

  bool _isEditing = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.connection != null;
    if (widget.connection != null) {
      final c = widget.connection!;
      _nameController.text = c.name;
      _serverIdController.text = c.serverId;
      _hostController.text = c.host;
      _portController.text = c.port.toString();
      _passwordController.text = c.password;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serverIdController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final serverId = _serverIdController.text.trim();
    final host = _hostController.text.trim();
    final portStr = _portController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty) {
      unawaited(MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'Informe o nome da conexão.',
          'Enter connection name.',
        ),
      ));
      return;
    }
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
    if (host.isEmpty) {
      unawaited(MessageModal.showError(
        context,
        message: appLocaleString(context, 'Informe o host.', 'Enter host.'),
      ));
      return;
    }
    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) {
      unawaited(MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'Informe uma porta valida (1-65535).',
          'Enter a valid port (1-65535).',
        ),
      ));
      return;
    }
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

    Navigator.of(context).pop(
      ConnectionFormResult(
        name: name,
        serverId: serverId,
        host: host,
        port: port,
        password: password,
      ),
    );
  }

  Future<void> _testConnection() async {
    final name = _nameController.text.trim();
    final serverId = _serverIdController.text.trim();
    final host = _hostController.text.trim();
    final portStr = _portController.text.trim();
    final password = _passwordController.text;

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
    if (host.isEmpty) {
      unawaited(MessageModal.showError(
        context,
        message: appLocaleString(context, 'Informe o host.', 'Enter host.'),
      ));
      return;
    }
    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) {
      unawaited(MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'Informe uma porta valida (1-65535).',
          'Enter a valid port (1-65535).',
        ),
      ));
      return;
    }
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

    setState(() => _isTesting = true);
    final provider = context.read<ServerConnectionProvider>();
    final tempConnection = ServerConnection(
      id: 'test',
      name: name.isEmpty ? appLocaleString(context, 'Teste', 'Test') : name,
      serverId: serverId,
      host: host,
      port: port,
      password: password,
      isOnline: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final ok = await provider.testConnection(tempConnection);
    if (!mounted) return;
    setState(() => _isTesting = false);
    if (ok) {
      if (!mounted) return;
      unawaited(MessageModal.showSuccess(
        context,
        message: appLocaleString(
          context,
          'Conexao bem-sucedida com $host:$port',
          'Successful connection to $host:$port',
        ),
      ));
    } else {
      if (!mounted) return;
      unawaited(MessageModal.showError(
        context,
        message:
            provider.error ??
            appLocaleString(
              context,
              'Falha ao conectar.',
              'Connection failed.',
            ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text(
        _isEditing
            ? appLocaleString(context, 'Editar conexão', 'Edit connection')
            : appLocaleString(context, 'Adicionar servidor', 'Add server'),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoLabel(
                label: appLocaleString(context, 'Nome', 'Name'),
                child: TextBox(
                  controller: _nameController,
                  placeholder: appLocaleString(
                    context,
                    'Nome da conexão',
                    'Connection name',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: appLocaleString(context, 'Host', 'Host'),
                child: TextBox(
                  controller: _hostController,
                  placeholder: appLocaleString(
                    context,
                    '127.0.0.1 ou endereco do servidor',
                    '127.0.0.1 or server address',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: appLocaleString(context, 'Porta', 'Port'),
                child: TextBox(
                  controller: _portController,
                  placeholder: appLocaleString(context, '9527', '9527'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: appLocaleString(context, 'ID do servidor', 'Server ID'),
                child: TextBox(
                  controller: _serverIdController,
                  placeholder: appLocaleString(
                    context,
                    'Identificador do servidor',
                    'Server identifier',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _passwordController,
                hint: appLocaleString(
                  context,
                  'Senha de acesso',
                  'Access password',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        Button(
          onPressed: _isTesting ? null : () => Navigator.of(context).pop(),
          child: Text(appLocaleString(context, 'Cancelar', 'Cancel')),
        ),
        Tooltip(
          message: appLocaleString(
            context,
            'Testar comunicacao com o servidor antes de salvar',
            'Test server communication before saving',
          ),
          child: Button(
            onPressed: _isTesting ? null : _testConnection,
            child: _isTesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: ProgressRing(strokeWidth: 2),
                  )
                : Text(
                    appLocaleString(
                      context,
                      'Testar conexão',
                      'Test connection',
                    ),
                  ),
          ),
        ),
        FilledButton(
          onPressed: _isTesting ? null : _submit,
          child: Text(appLocaleString(context, 'Salvar', 'Save')),
        ),
      ],
    );
  }
}
