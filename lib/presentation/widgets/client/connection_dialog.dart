import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/presentation/widgets/client/connection_form_result.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

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
      MessageModal.showError(context, message: 'Informe o nome da conexão.');
      return;
    }
    if (serverId.isEmpty) {
      MessageModal.showError(context, message: 'Informe o Server ID.');
      return;
    }
    if (host.isEmpty) {
      MessageModal.showError(context, message: 'Informe o host.');
      return;
    }
    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) {
      MessageModal.showError(context, message: 'Informe uma porta válida (1-65535).');
      return;
    }
    if (password.isEmpty) {
      MessageModal.showError(context, message: 'Informe a senha.');
      return;
    }

    Navigator.of(context).pop(ConnectionFormResult(
      name: name,
      serverId: serverId,
      host: host,
      port: port,
      password: password,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text(_isEditing ? 'Editar Conexão' : 'Adicionar Servidor'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoLabel(
                label: 'Nome',
                child: TextBox(
                  controller: _nameController,
                  placeholder: 'Nome da conexão',
                ),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: 'Host',
                child: TextBox(
                  controller: _hostController,
                  placeholder: '127.0.0.1 ou endereço do servidor',
                ),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: 'Porta',
                child: TextBox(
                  controller: _portController,
                  placeholder: '9527',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: 'Server ID',
                child: TextBox(
                  controller: _serverIdController,
                  placeholder: 'Identificador do servidor',
                ),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _passwordController,
                hint: 'Senha de acesso',
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
