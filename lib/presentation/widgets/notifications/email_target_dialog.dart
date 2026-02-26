import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class EmailTargetDialog extends StatefulWidget {
  const EmailTargetDialog({
    required this.emailConfigId,
    required this.defaultNotifyOnSuccess,
    required this.defaultNotifyOnError,
    required this.defaultNotifyOnWarning,
    super.key,
    this.initialTarget,
  });

  final String emailConfigId;
  final bool defaultNotifyOnSuccess;
  final bool defaultNotifyOnError;
  final bool defaultNotifyOnWarning;
  final EmailNotificationTarget? initialTarget;

  static Future<EmailNotificationTarget?> show(
    BuildContext context, {
    required String emailConfigId,
    required bool defaultNotifyOnSuccess,
    required bool defaultNotifyOnError,
    required bool defaultNotifyOnWarning,
    EmailNotificationTarget? initialTarget,
  }) {
    return showDialog<EmailNotificationTarget>(
      context: context,
      builder: (context) => EmailTargetDialog(
        emailConfigId: emailConfigId,
        defaultNotifyOnSuccess: defaultNotifyOnSuccess,
        defaultNotifyOnError: defaultNotifyOnError,
        defaultNotifyOnWarning: defaultNotifyOnWarning,
        initialTarget: initialTarget,
      ),
    );
  }

  @override
  State<EmailTargetDialog> createState() => _EmailTargetDialogState();
}

class _EmailTargetDialogState extends State<EmailTargetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _recipientController;

  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    final target = widget.initialTarget;
    _recipientController = TextEditingController(
      text: target?.recipientEmail ?? '',
    );
    _enabled = target?.enabled ?? true;
  }

  @override
  void dispose() {
    _recipientController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final current = widget.initialTarget;
    final target = EmailNotificationTarget(
      id: current?.id,
      emailConfigId: widget.emailConfigId,
      recipientEmail: _recipientController.text.trim(),
      notifyOnSuccess:
          current?.notifyOnSuccess ?? widget.defaultNotifyOnSuccess,
      notifyOnError: current?.notifyOnError ?? widget.defaultNotifyOnError,
      notifyOnWarning:
          current?.notifyOnWarning ?? widget.defaultNotifyOnWarning,
      enabled: _enabled,
      createdAt: current?.createdAt,
    );

    Navigator.of(context).pop(target);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialTarget != null;

    return ContentDialog(
      constraints: const BoxConstraints(
        minWidth: 620,
        maxWidth: 620,
      ),
      title: Row(
        children: [
          const Icon(FluentIcons.group),
          const SizedBox(width: 12),
          Text(isEditing ? 'Editar destinatario' : 'Novo destinatario'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: _recipientController,
              label: 'E-mail do destinatario',
              keyboardType: TextInputType.emailAddress,
              hint: 'destino@exemplo.com',
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'E-mail é obrigatório';
                }
                if (!value.contains('@')) {
                  return 'E-mail invalido';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _TargetStatusSection(
              enabled: _enabled,
              onEnabledChanged: (value) {
                setState(() {
                  _enabled = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        const CancelButton(),
        SaveButton(onPressed: _submit, isEditing: isEditing),
      ],
    );
  }
}

class _TargetStatusSection extends StatelessWidget {
  const _TargetStatusSection({
    required this.enabled,
    required this.onEnabledChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Os tipos de notificação (sucesso/erro/aviso) são definidos no modal da configuração SMTP.',
        ),
        const SizedBox(height: 10),
        _TargetToggleField(
          label: 'Destinatario ativo',
          value: enabled,
          onChanged: onEnabledChanged,
        ),
      ],
    );
  }
}

class _TargetToggleField extends StatelessWidget {
  const _TargetToggleField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InfoLabel(
      label: label,
      child: ToggleSwitch(
        checked: value,
        onChanged: onChanged,
      ),
    );
  }
}
