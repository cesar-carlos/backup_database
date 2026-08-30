import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/core/utils/database_type_metadata.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class RemoteScheduleCreateDialog extends StatefulWidget {
  const RemoteScheduleCreateDialog({this.template, super.key});

  final Schedule? template;

  @override
  State<RemoteScheduleCreateDialog> createState() =>
      _RemoteScheduleCreateDialogState();
}

class _RemoteScheduleCreateDialogState
    extends State<RemoteScheduleCreateDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _databaseConfigIdController =
      TextEditingController();
  final TextEditingController _backupFolderController = TextEditingController();
  final TextEditingController _intervalMinutesController =
      TextEditingController(text: '60');

  ScheduleType _scheduleType = ScheduleType.daily;
  DatabaseType _databaseType = DatabaseType.sqlServer;
  int _hour = 2;
  int _minute = 0;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    if (template != null) {
      _databaseConfigIdController.text = template.databaseConfigId;
      _databaseType = template.databaseType;
      _backupFolderController.text = template.backupFolder;
      _scheduleType = scheduleTypeFromString(template.scheduleType);
      _parseScheduleConfig(template.scheduleConfig);
    } else {
      _backupFolderController.text = _defaultBackupFolder();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _databaseConfigIdController.dispose();
    _backupFolderController.dispose();
    _intervalMinutesController.dispose();
    super.dispose();
  }

  String _defaultBackupFolder() {
    final systemTemp =
        Platform.environment['TEMP'] ??
        Platform.environment['TMP'] ??
        r'C:\Temp';
    return '$systemTemp\\BackupDatabase';
  }

  void _parseScheduleConfig(String configJson) {
    try {
      final config = jsonDecode(configJson) as Map<String, dynamic>;
      switch (_scheduleType) {
        case ScheduleType.daily:
        case ScheduleType.weekly:
        case ScheduleType.monthly:
          _hour = (config['hour'] as int?) ?? _hour;
          _minute = (config['minute'] as int?) ?? _minute;
        case ScheduleType.interval:
          final minutes = (config['intervalMinutes'] as int?) ?? 60;
          _intervalMinutesController.text = minutes.toString();
      }
    } on Object {
      // Mantém defaults do dialogo.
    }
  }

  String _buildScheduleConfigJson() {
    switch (_scheduleType) {
      case ScheduleType.daily:
        return jsonEncode({'hour': _hour, 'minute': _minute});
      case ScheduleType.weekly:
        return jsonEncode({
          'daysOfWeek': [1],
          'hour': _hour,
          'minute': _minute,
        });
      case ScheduleType.monthly:
        return jsonEncode({
          'daysOfMonth': [1],
          'hour': _hour,
          'minute': _minute,
        });
      case ScheduleType.interval:
        final minutes =
            int.tryParse(_intervalMinutesController.text.trim()) ?? 60;
        return jsonEncode({'intervalMinutes': minutes});
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _validationError = 'Informe o nome do agendamento.');
      return;
    }
    final databaseConfigId = _databaseConfigIdController.text.trim();
    if (databaseConfigId.isEmpty) {
      setState(
        () => _validationError = 'Informe o ID da configuração de banco.',
      );
      return;
    }
    final backupFolder = _backupFolderController.text.trim();
    if (backupFolder.isEmpty) {
      setState(() => _validationError = 'Informe a pasta de backup.');
      return;
    }

    final schedule = Schedule(
      name: name,
      databaseConfigId: databaseConfigId,
      databaseType: _databaseType,
      scheduleType: _scheduleType.toValue(),
      scheduleConfig: _buildScheduleConfigJson(),
      destinationIds: widget.template?.destinationIds ?? const <String>[],
      backupFolder: backupFolder,
    );
    Navigator.of(context).pop(schedule);
  }

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);
    final showTimeFields = _scheduleType != ScheduleType.interval;

    return AppDialogShell(
      title: Text(
        appLocaleString(
          context,
          'Novo agendamento remoto',
          'New remote schedule',
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_validationError != null) ...[
              AppCallout(
                message: _validationError!,
                tone: AppCalloutTone.warning,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AppTextField(
              controller: _nameController,
              label: appLocaleString(
                context,
                'Nome do agendamento',
                'Schedule name',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdown<ScheduleType>(
              label: appLocaleString(context, 'Tipo', 'Type'),
              placeholder: Text(
                appLocaleString(context, 'Tipo', 'Type'),
              ),
              value: _scheduleType,
              items: ScheduleType.values
                  .map(
                    (type) => ComboBoxItem(
                      value: type,
                      child: Text(texts.scheduleTypeName(type)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _scheduleType = value);
              },
            ),
            if (showTimeFields) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                appLocaleString(context, 'Horário', 'Time'),
                style: FluentTheme.of(context).typography.bodyStrong,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: NumberBox(
                      value: _hour.toDouble(),
                      min: 0,
                      max: 23,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _hour = value.round());
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: NumberBox(
                      value: _minute.toDouble(),
                      min: 0,
                      max: 59,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _minute = value.round());
                      },
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _intervalMinutesController,
                label: appLocaleString(
                  context,
                  'Intervalo (minutos)',
                  'Interval (minutes)',
                ),
              ),
            ],
            if (widget.template == null) ...[
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _databaseConfigIdController,
                label: appLocaleString(
                  context,
                  'ID da configuração de banco',
                  'Database config ID',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppDropdown<DatabaseType>(
                label: appLocaleString(
                  context,
                  'Tipo de banco',
                  'Database type',
                ),
                value: _databaseType,
                items: DatabaseType.values
                    .map(
                      (type) => ComboBoxItem(
                        value: type,
                        child: Text(
                          DatabaseTypeMetadata.of(type).chipLabel,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _databaseType = value);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _backupFolderController,
                label: appLocaleString(
                  context,
                  'Pasta de backup no servidor',
                  'Backup folder on server',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        CancelButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton.primary(
          label: appLocaleString(context, 'Criar', 'Create'),
          onPressed: _submit,
        ),
      ],
    );
  }
}
