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
  bool _notifyOnSuccess = true;
  bool _notifyOnError = true;
  bool _notifyOnWarning = true;

  @override
  void initState() {
    super.initState();
    final target = widget.initialTarget;
    _recipientController = TextEditingController(
      text: target?.recipientEmail ?? '',
    );
    _enabled = target?.enabled ?? true;
    _notifyOnSuccess = target?.notifyOnSuccess ?? widget.defaultNotifyOnSuccess;
    _notifyOnError = target?.notifyOnError ?? widget.defaultNotifyOnError;
    _notifyOnWarning = target?.notifyOnWarning ?? widget.defaultNotifyOnWarning;
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
      notifyOnSuccess: _notifyOnSuccess,
      notifyOnError: _notifyOnError,
      notifyOnWarning: _notifyOnWarning,
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
              notifyOnSuccess: _notifyOnSuccess,
              notifyOnError: _notifyOnError,
              notifyOnWarning: _notifyOnWarning,
              onEnabledChanged: (value) {
                setState(() {
                  _enabled = value;
                });
              },
              onNotifyOnSuccessChanged: (value) {
                setState(() {
                  _notifyOnSuccess = value;
                });
              },
              onNotifyOnErrorChanged: (value) {
                setState(() {
                  _notifyOnError = value;
                });
              },
              onNotifyOnWarningChanged: (value) {
                setState(() {
                  _notifyOnWarning = value;
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
    required this.notifyOnSuccess,
    required this.notifyOnError,
    required this.notifyOnWarning,
    required this.onEnabledChanged,
    required this.onNotifyOnSuccessChanged,
    required this.onNotifyOnErrorChanged,
    required this.onNotifyOnWarningChanged,
  });

  final bool enabled;
  final bool notifyOnSuccess;
  final bool notifyOnError;
  final bool notifyOnWarning;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onNotifyOnSuccessChanged;
  final ValueChanged<bool> onNotifyOnErrorChanged;
  final ValueChanged<bool> onNotifyOnWarningChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Defina quais tipos de evento este destinatário receberá. '
          'Cada destinatário pode ter configurações diferentes de notificação.',
        ),
        const SizedBox(height: 10),
        _TargetToggleField(
          label: 'Receber notificação de sucesso',
          value: notifyOnSuccess,
          onChanged: onNotifyOnSuccessChanged,
        ),
        const SizedBox(height: 10),
        _TargetToggleField(
          label: 'Receber notificação de erro',
          value: notifyOnError,
          onChanged: onNotifyOnErrorChanged,
        ),
        const SizedBox(height: 10),
        _TargetToggleField(
          label: 'Receber notificação de aviso',
          value: notifyOnWarning,
          onChanged: onNotifyOnWarningChanged,
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
