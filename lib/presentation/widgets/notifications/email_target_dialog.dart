import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
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
    final theme = FluentTheme.of(context);

    return ContentDialog(
      constraints: const BoxConstraints(
        minWidth: 620,
        maxWidth: 620,
      ),
      title: Row(
        children: [
          const Icon(FluentIcons.group),
          const SizedBox(width: 12),
          Text(
            isEditing
                ? appLocaleString(
                    context,
                    'Editar destinatário',
                    'Edit recipient',
                  )
                : appLocaleString(
                    context,
                    'Novo destinatário',
                    'New recipient',
                  ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
            Text(
              appLocaleString(
                context,
                'Identificação',
                'Identification',
              ),
              style: theme.typography.subtitle?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appLocaleString(
                context,
                'Defina o e-mail e os tipos de evento que esse contato receberá.',
                'Define the e-mail address and the event types this contact should receive.',
              ),
              style: theme.typography.caption,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _recipientController,
              label: appLocaleString(
                context,
                'E-mail do destinatário',
                'Recipient e-mail',
              ),
              keyboardType: TextInputType.emailAddress,
              hint: appLocaleString(
                context,
                'destino@exemplo.com',
                'recipient@example.com',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return appLocaleString(
                    context,
                    'E-mail é obrigatório.',
                    'E-mail is required.',
                  );
                }
                if (!value.contains('@')) {
                  return appLocaleString(
                    context,
                    'E-mail inválido.',
                    'Invalid e-mail.',
                  );
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            Text(
              appLocaleString(
                context,
                'Eventos',
                'Events',
              ),
              style: theme.typography.subtitle?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appLocaleString(
                context,
                'Ative somente os eventos que devem gerar notificações para este destinatário.',
                'Enable only the events that should notify this recipient.',
              ),
              style: theme.typography.caption,
            ),
            const SizedBox(height: 16),
            _TargetToggleField(
              label: appLocaleString(
                context,
                'Receber notificações de sucesso',
                'Notify on success',
              ),
              description: appLocaleString(
                context,
                'Usado para confirmar execuções concluídas sem erro.',
                'Used to confirm executions that finished successfully.',
              ),
              value: _notifyOnSuccess,
              onChanged: (value) {
                setState(() {
                  _notifyOnSuccess = value;
                });
              },
            ),
            const SizedBox(height: 12),
            _TargetToggleField(
              label: appLocaleString(
                context,
                'Receber notificações de erro',
                'Notify on error',
              ),
              description: appLocaleString(
                context,
                'Priorize para contatos de suporte ou operação.',
                'Prioritize for support or operations contacts.',
              ),
              value: _notifyOnError,
              onChanged: (value) {
                setState(() {
                  _notifyOnError = value;
                });
              },
            ),
            const SizedBox(height: 12),
            _TargetToggleField(
              label: appLocaleString(
                context,
                'Receber notificações de aviso',
                'Notify on warning',
              ),
              description: appLocaleString(
                context,
                'Inclui eventos intermediários ou pendências operacionais.',
                'Includes intermediate events or operational warnings.',
              ),
              value: _notifyOnWarning,
              onChanged: (value) {
                setState(() {
                  _notifyOnWarning = value;
                });
              },
            ),
            const SizedBox(height: 20),
            Text(
              appLocaleString(context, 'Status', 'Status'),
              style: theme.typography.subtitle?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _TargetToggleField(
              label: appLocaleString(
                context,
                'Destinatário ativo',
                'Recipient active',
              ),
              description: appLocaleString(
                context,
                'Destinatários inativos permanecem cadastrados, mas não recebem notificações.',
                'Inactive recipients remain registered, but do not receive notifications.',
              ),
              value: _enabled,
              onChanged: (value) {
                setState(() {
                  _enabled = value;
                });
              },
            ),
            ],
          ),
        ),
      ),
      actions: [
        const CancelButton(),
        SaveButton(onPressed: _submit, isEditing: isEditing),
      ],
    );
  }
}

class _TargetToggleField extends StatelessWidget {
  const _TargetToggleField({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final captionStyle = FluentTheme.of(context).typography.caption;

    final outline = context.colors.outline;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: outline.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: outline.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(description, style: captionStyle),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ToggleSwitch(
            checked: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
