import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/schedule_dialog_strings.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sql_server_backup_schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class ScheduleDialog extends StatefulWidget {
  const ScheduleDialog({super.key, this.schedule});
  final Schedule? schedule;

  static Future<Schedule?> show(BuildContext context, {Schedule? schedule}) {
    return showDialog<Schedule>(
      context: context,
      builder: (context) => ScheduleDialog(schedule: schedule),
    );
  }

  @override
  State<ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<ScheduleDialog> {
  final _formKey = GlobalKey<FormState>();
  int _selectedTabIndex = 0;
  bool _nameFieldTouched = false;

  final _nameController = TextEditingController();
  final _intervalMinutesController = TextEditingController();
  final _backupFolderController = TextEditingController();
  final _postBackupScriptController = TextEditingController();
  final _backupTimeoutMinutesController = TextEditingController();
  final _verifyTimeoutMinutesController = TextEditingController();

  DatabaseType _databaseType = DatabaseType.sqlServer;
  String? _selectedDatabaseConfigId;
  ScheduleType _scheduleType = ScheduleType.daily;
  BackupType _backupType = BackupType.full;
  bool _truncateLog = true;
  List<String> _selectedDestinationIds = [];
  bool _compressBackup = true;
  CompressionFormat _compressionFormat = CompressionFormat.zip;
  bool _isEnabled = true;
  bool _enableChecksum = false;
  bool _verifyAfterBackup = false;
  VerifyPolicy _verifyPolicy = VerifyPolicy.bestEffort;
  bool _compression = false;

  Duration _backupTimeout = const Duration(hours: 2);
  Duration _verifyTimeout = const Duration(minutes: 30);

  int? _maxTransferSize;
  int? _bufferCount;
  int? _blockSize;
  int _stripingCount = 1;
  int _statsPercent = 10;

  int _hour = 0;
  int _minute = 0;
  List<int> _selectedDaysOfWeek = [1];
  List<int> _selectedDaysOfMonth = [1];
  int _intervalMinutes = 60;

  List<SqlServerConfig> _sqlServerConfigs = [];
  List<SybaseConfig> _sybaseConfigs = [];
  List<PostgresConfig> _postgresConfigs = [];
  List<BackupDestination> _destinations = [];
  bool _isLoading = true;

  bool get isEditing => widget.schedule != null;

  BackupType _normalizeBackupTypeForDatabase(
    DatabaseType databaseType,
    BackupType backupType,
  ) {
    if (databaseType != DatabaseType.postgresql &&
        backupType == BackupType.fullSingle) {
      return BackupType.full;
    }
    if (databaseType == DatabaseType.sybase &&
        backupType == BackupType.differential) {
      return BackupType.full;
    }
    return backupType;
  }

  @override
  void initState() {
    super.initState();
    _intervalMinutesController.text = _intervalMinutes.toString();
    _backupFolderController.text = _getDefaultBackupFolder();
    _backupTimeoutMinutesController.text = _backupTimeout.inMinutes.toString();
    _verifyTimeoutMinutesController.text = _verifyTimeout.inMinutes.toString();

    if (widget.schedule != null) {
      _nameController.text = widget.schedule!.name;
      _databaseType = widget.schedule!.databaseType;
      _selectedDatabaseConfigId = widget.schedule!.databaseConfigId;
      _scheduleType = scheduleTypeFromString(widget.schedule!.scheduleType);
      _backupType = _normalizeBackupTypeForDatabase(
        _databaseType,
        widget.schedule!.backupType,
      );
      _truncateLog = widget.schedule!.truncateLog;
      _selectedDestinationIds = List.from(widget.schedule!.destinationIds);
      _compressBackup = widget.schedule!.compressBackup;
      _compressionFormat =
          widget.schedule!.compressionFormat ?? CompressionFormat.zip;
      _isEnabled = widget.schedule!.enabled;
      _enableChecksum = widget.schedule!.enableChecksum;
      _verifyAfterBackup = widget.schedule!.verifyAfterBackup;
      _verifyPolicy = widget.schedule!.verifyPolicy;
      _backupTimeout = widget.schedule!.backupTimeout;
      _verifyTimeout = widget.schedule!.verifyTimeout;
      _backupTimeoutMinutesController.text = _backupTimeout.inMinutes
          .toString();
      _verifyTimeoutMinutesController.text = _verifyTimeout.inMinutes
          .toString();

      switch (widget.schedule) {
        case SqlServerBackupSchedule(:final sqlServerBackupOptions):
          _compression = sqlServerBackupOptions.compression;
          _maxTransferSize = sqlServerBackupOptions.maxTransferSize;
          _bufferCount = sqlServerBackupOptions.bufferCount;
          _blockSize = sqlServerBackupOptions.blockSize;
          _stripingCount = sqlServerBackupOptions.stripingCount;
          _statsPercent = sqlServerBackupOptions.statsPercent;
        case _:
      }

      _backupFolderController.text = widget.schedule!.backupFolder.isNotEmpty
          ? widget.schedule!.backupFolder
          : _getDefaultBackupFolder();
      _postBackupScriptController.text =
          widget.schedule!.postBackupScript ?? '';

      _parseScheduleConfig(widget.schedule!.scheduleConfig);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  String _getDefaultBackupFolder() {
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
          _hour = (config['hour'] as int?) ?? 0;
          _minute = (config['minute'] as int?) ?? 0;
        case ScheduleType.weekly:
          _selectedDaysOfWeek =
              (config['daysOfWeek'] as List?)?.cast<int>() ?? [1];
          _hour = (config['hour'] as int?) ?? 0;
          _minute = (config['minute'] as int?) ?? 0;
        case ScheduleType.monthly:
          _selectedDaysOfMonth =
              (config['daysOfMonth'] as List?)?.cast<int>() ?? [1];
          _hour = (config['hour'] as int?) ?? 0;
          _minute = (config['minute'] as int?) ?? 0;
        case ScheduleType.interval:
          _intervalMinutes = (config['intervalMinutes'] as int?) ?? 60;
          _intervalMinutesController.text = _intervalMinutes.toString();
      }
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao carregar config de agendamento', e, s);
    }
  }

  Future<void> _loadData() async {
    final sqlServerProvider = context.read<SqlServerConfigProvider>();
    final sybaseProvider = context.read<SybaseConfigProvider>();
    final postgresProvider = context.read<PostgresConfigProvider>();
    final destinationProvider = context.read<DestinationProvider>();

    await Future.wait([
      sqlServerProvider.loadConfigs(),
      sybaseProvider.loadConfigs(),
      postgresProvider.loadConfigs(),
      destinationProvider.loadDestinations(),
    ]);

    if (mounted) {
      setState(() {
        _sqlServerConfigs = sqlServerProvider.configs;
        _sybaseConfigs = sybaseProvider.configs;
        _postgresConfigs = postgresProvider.configs;
        _destinations = destinationProvider.destinations;

        if (_selectedDatabaseConfigId != null) {
          final exists = _databaseType == DatabaseType.sqlServer
              ? _sqlServerConfigs.any((c) => c.id == _selectedDatabaseConfigId)
              : _databaseType == DatabaseType.sybase
              ? _sybaseConfigs.any((c) => c.id == _selectedDatabaseConfigId)
              : _postgresConfigs.any((c) => c.id == _selectedDatabaseConfigId);

          if (!exists) {
            _selectedDatabaseConfigId = null;
          }
        }

        _selectedDestinationIds.removeWhere((id) {
          return !_destinations.any((d) => d.id == id);
        });

        _isLoading = false;
      });
    }
  }

  void _onBackupTypeChanged() {
    if (_backupType != BackupType.log) {
      _truncateLog = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _intervalMinutesController.dispose();
    _backupFolderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(
        minWidth: 550,
        maxWidth: 650,
        maxHeight: 750,
      ),
      title: Row(
        children: [
          const Icon(FluentIcons.calendar, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(
            isEditing
                ? ScheduleDialogStrings.editSchedule
                : ScheduleDialogStrings.newSchedule,
            style: FluentTheme.of(context).typography.title,
          ),
        ],
      ),
      content: Container(
        constraints: const BoxConstraints(maxHeight: 700),
        child: _isLoading
            ? const Center(child: ProgressRing())
            : Form(
                key: _formKey,
                child: TabView(
                  currentIndex: _selectedTabIndex,
                  onChanged: (index) {
                    setState(() {
                      _selectedTabIndex = index;
                    });
                  },
                  tabs: [
                    Tab(
                      text: const Text(ScheduleDialogStrings.tabGeneral),
                      icon: const Icon(FluentIcons.settings),
                      body: _buildGeneralTab(),
                    ),
                    Tab(
                      text: const Text(ScheduleDialogStrings.tabSettings),
                      icon: const Icon(FluentIcons.folder),
                      body: _buildSettingsTab(),
                    ),
                    Tab(
                      text: const Text(ScheduleDialogStrings.tabScriptSql),
                      icon: const Icon(FluentIcons.code),
                      body: _buildScriptTab(),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        const CancelButton(),
        SaveButton(onPressed: _save, isEditing: isEditing),
      ],
    );
  }

  Widget _buildGeneralTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _nameController,
            label: 'Nome do Agendamento',
            hint: 'Ex: Backup Diário Produção',
            prefixIcon: const Icon(FluentIcons.tag),
            validator: (value) {
              if (_nameFieldTouched) {
                if (value == null || value.trim().isEmpty) {
                  return 'Nome é obrigatório';
                }
              }
              return null;
            },
            onChanged: (value) {
              if (!_nameFieldTouched) {
                setState(() {
                  _nameFieldTouched = true;
                });
              }
            },
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Banco de Dados'),
          const SizedBox(height: 12),
          AppDropdown<DatabaseType>(
            label: 'Tipo de Banco',
            value: _databaseType,
            placeholder: const Text('Tipo de Banco'),
            items: DatabaseType.values.map((type) {
              return ComboBoxItem<DatabaseType>(
                value: type,
                child: Text(_getDatabaseTypeName(type)),
              );
            }).toList(),
            onChanged: isEditing
                ? null
                : (value) {
                    if (value != null) {
                      setState(() {
                        _selectedDatabaseConfigId = null;
                        _databaseType = value;
                        _backupType = _normalizeBackupTypeForDatabase(
                          _databaseType,
                          _backupType,
                        );
                        _onBackupTypeChanged();
                      });
                      _formKey.currentState?.validate();
                    }
                  },
          ),
          const SizedBox(height: 16),
          Builder(
            key: ValueKey(
              'database_config_dropdown_${_databaseType}_${_selectedDatabaseConfigId ?? 'null'}',
            ),
            builder: (context) => _buildDatabaseConfigDropdown(),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Tipo de Backup'),
          const SizedBox(height: 12),
          Consumer<LicenseProvider>(
            builder: (context, licenseProvider, child) {
              final hasDifferential =
                  licenseProvider.hasValidLicense &&
                  licenseProvider.currentLicense!.hasFeature(
                    LicenseFeatures.differentialBackup,
                  );
              final hasLog =
                  licenseProvider.hasValidLicense &&
                  licenseProvider.currentLicense!.hasFeature(
                    LicenseFeatures.logBackup,
                  );

              final isSybaseConvertedDifferential =
                  _databaseType == DatabaseType.sybase &&
                  isEditing &&
                  (widget.schedule?.isConvertedDifferential ?? false);

              List<BackupType> allTypes;
              if (_databaseType == DatabaseType.sybase) {
                allTypes = [
                  BackupType.full,
                  BackupType.log,
                  if (isSybaseConvertedDifferential) BackupType.differential,
                ];
              } else if (_databaseType == DatabaseType.postgresql) {
                allTypes = [
                  BackupType.full,
                  BackupType.fullSingle,
                  BackupType.differential,
                  BackupType.log,
                ];
              } else {
                allTypes = [
                  BackupType.full,
                  BackupType.differential,
                  BackupType.log,
                ];
              }

              return AppDropdown<BackupType>(
                label: 'Tipo de Backup',
                value: _backupType,
                placeholder: const Text('Tipo de Backup'),
                items: allTypes.map((type) {
                  final isDifferentialBlocked =
                      type == BackupType.differential && !hasDifferential;
                  final isLogBlocked = type == BackupType.log && !hasLog;
                  final isSybaseConvertedType =
                      _databaseType == DatabaseType.sybase &&
                      type == BackupType.differential;
                  final isBlocked = isDifferentialBlocked || isLogBlocked;

                  return ComboBoxItem<BackupType>(
                    value: type,
                    enabled: !isBlocked,
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  isBlocked
                                      ? '${type.displayName} (Requer licença)'
                                      : isSybaseConvertedType
                                      ? '${type.displayName} (convertido)'
                                      : type.displayName,
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    color: isBlocked
                                        ? FluentTheme.of(context)
                                              .resources
                                              .controlStrokeColorDefault
                                              .withValues(alpha: 0.4)
                                        : isSybaseConvertedType
                                        ? FluentTheme.of(
                                            context,
                                          ).accentColor.defaultBrushFor(
                                            FluentTheme.of(context).brightness,
                                          )
                                        : null,
                                    fontStyle: isSybaseConvertedType
                                        ? FontStyle.italic
                                        : null,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isBlocked) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  FluentIcons.lock,
                                  size: 16,
                                  color: FluentTheme.of(context)
                                      .resources
                                      .controlStrokeColorDefault
                                      .withValues(alpha: 0.4),
                                ),
                              ],
                              if (isSybaseConvertedType) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  FluentIcons.switch_widget,
                                  size: 14,
                                  color: FluentTheme.of(context).accentColor,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    final hasDifferential =
                        licenseProvider.hasValidLicense &&
                        licenseProvider.currentLicense!.hasFeature(
                          LicenseFeatures.differentialBackup,
                        );
                    final hasLog =
                        licenseProvider.hasValidLicense &&
                        licenseProvider.currentLicense!.hasFeature(
                          LicenseFeatures.logBackup,
                        );

                    final isDifferentialBlocked =
                        value == BackupType.differential && !hasDifferential;
                    final isLogBlocked = value == BackupType.log && !hasLog;

                    if (isDifferentialBlocked || isLogBlocked) {
                      MessageModal.showWarning(
                        context,
                        message:
                            'Este tipo de backup requer uma licença válida. '
                            'Acesse Configurações > Licenciamento para mais informações.',
                      );
                      return;
                    }

                    setState(() {
                      _backupType = value;
                      _onBackupTypeChanged();
                    });
                  }
                },
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            _getBackupTypeDescription(_backupType),
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Agendamento'),
          const SizedBox(height: 12),
          Consumer<LicenseProvider>(
            builder: (context, licenseProvider, child) {
              final hasInterval =
                  licenseProvider.hasValidLicense &&
                  licenseProvider.currentLicense!.hasFeature(
                    LicenseFeatures.intervalSchedule,
                  );

              return AppDropdown<ScheduleType>(
                label: 'Frequência',
                value: _scheduleType,
                placeholder: const Text('Frequência'),
                items: ScheduleType.values.map((type) {
                  final isIntervalBlocked =
                      type == ScheduleType.interval && !hasInterval;

                  return ComboBoxItem<ScheduleType>(
                    value: type,
                    enabled: !isIntervalBlocked,
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  isIntervalBlocked
                                      ? '${_getScheduleTypeName(type)} (Requer licença)'
                                      : _getScheduleTypeName(type),
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    color: isIntervalBlocked
                                        ? FluentTheme.of(context)
                                              .resources
                                              .controlStrokeColorDefault
                                              .withValues(alpha: 0.4)
                                        : null,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isIntervalBlocked) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  FluentIcons.lock,
                                  size: 16,
                                  color: FluentTheme.of(context)
                                      .resources
                                      .controlStrokeColorDefault
                                      .withValues(alpha: 0.4),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    final hasInterval =
                        licenseProvider.hasValidLicense &&
                        licenseProvider.currentLicense!.hasFeature(
                          LicenseFeatures.intervalSchedule,
                        );

                    if (value == ScheduleType.interval && !hasInterval) {
                      MessageModal.showWarning(
                        context,
                        message:
                            'Agendamento por intervalo requer uma licença válida. '
                            'Acesse Configurações > Licenciamento para mais informações.',
                      );
                      return;
                    }

                    setState(() {
                      _scheduleType = value;
                    });
                  }
                },
              );
            },
          ),
          const SizedBox(height: 16),
          if (_backupType == BackupType.log)
            InfoLabel(
              label: 'Truncar log após backup',
              child: ToggleSwitch(
                checked: _truncateLog,
                onChanged: (value) {
                  setState(() {
                    _truncateLog = value;
                  });
                },
              ),
            ),
          if (_backupType == BackupType.log) const SizedBox(height: 8),
          if (_backupType == BackupType.log)
            Text(
              'Quando habilitado, o backup de log libera espaço (SQL Server: padrão; Sybase: depende do motor).',
              style: FluentTheme.of(context).typography.caption,
            ),
          const SizedBox(height: 16),
          _buildScheduleFields(),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle(ScheduleDialogStrings.destinations),
          const SizedBox(height: 12),
          _buildDestinationSelector(),
          const SizedBox(height: 24),
          _buildSectionTitle(ScheduleDialogStrings.backupFolderSection),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _backupFolderController,
                  label: ScheduleDialogStrings.backupFolderLabel,
                  hint: ScheduleDialogStrings.backupFolderHint,
                  prefixIcon: const Icon(FluentIcons.folder),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return ScheduleDialogStrings.backupFolderRequired;
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: IconButton(
                  icon: const Icon(FluentIcons.folder_open),
                  onPressed: _selectBackupFolder,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ScheduleDialogStrings.backupFolderDescription,
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(ScheduleDialogStrings.options),
          const SizedBox(height: 12),
          InfoLabel(
            label: ScheduleDialogStrings.compressBackup,
            child: ToggleSwitch(
              checked: _compressBackup,
              onChanged: (value) {
                setState(() {
                  _compressBackup = value;
                  if (!value) {
                    _compressionFormat = CompressionFormat.none;
                  } else if (_compressionFormat == CompressionFormat.none) {
                    _compressionFormat = CompressionFormat.zip;
                  }
                });
              },
            ),
          ),
          if (_compressBackup) ...[
            const SizedBox(height: 16),
            AppDropdown<CompressionFormat>(
              label: ScheduleDialogStrings.compressionFormat,
              value: _compressionFormat,
              placeholder: const Text(
                ScheduleDialogStrings.compressionFormatPlaceholder,
              ),
              items: const [
                ComboBoxItem<CompressionFormat>(
                  value: CompressionFormat.zip,
                  child: Text(ScheduleDialogStrings.compressionFormatZip),
                ),
                ComboBoxItem<CompressionFormat>(
                  value: CompressionFormat.rar,
                  child: Text(ScheduleDialogStrings.compressionFormatRar),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _compressionFormat = value;
                  });
                }
              },
            ),
          ],
          const SizedBox(height: 16),
          InfoLabel(
            label: ScheduleDialogStrings.schedulingEnabled,
            child: ToggleSwitch(
              checked: _isEnabled,
              onChanged: (value) {
                setState(() {
                  _isEnabled = value;
                });
              },
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(ScheduleDialogStrings.timeoutsSection),
          const SizedBox(height: 12),
          InfoLabel(
            label: ScheduleDialogStrings.backupTimeout,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 120,
                  child: InfoLabel(
                    label: ScheduleDialogStrings.minutes,
                    child: NumericField(
                      controller: _backupTimeoutMinutesController,
                      label: '',
                      minValue: 1,
                      maxValue: 1440,
                      onChanged: (value) {
                        final minutes = int.tryParse(value) ?? 120;
                        setState(() {
                          _backupTimeout = Duration(minutes: minutes);
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    ScheduleDialogStrings.max24Hours,
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: ScheduleDialogStrings.verifyTimeout,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 120,
                  child: InfoLabel(
                    label: ScheduleDialogStrings.minutes,
                    child: NumericField(
                      controller: _verifyTimeoutMinutesController,
                      label: '',
                      minValue: 1,
                      maxValue: 1440,
                      onChanged: (value) {
                        final minutes = int.tryParse(value) ?? 30;
                        setState(() {
                          _verifyTimeout = Duration(minutes: minutes);
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    ScheduleDialogStrings.max24Hours,
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            ScheduleDialogStrings.timeoutsDescription,
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: 24),
          _buildIntegrityOptions(),
          if (_databaseType == DatabaseType.sqlServer)
            _buildAdvancedPerformanceOptions(),
        ],
      ),
    );
  }

  Widget _buildAdvancedPerformanceOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('Performance Avançada (SQL Server)'),
        const SizedBox(height: 12),
        InfoLabel(
          label: 'Compressão Nativa (COMPRESSION)',
          child: ToggleSwitch(
            checked: _compression,
            onChanged: (value) {
              setState(() {
                _compression = value;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Compressão nativa do SQL Server. Requer edição Enterprise do SQL Server 2008+.',
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        AppDropdown<int?>(
          label: 'Tamanho Máximo de Transferência (MAXTRANSFERSIZE)',
          value: _maxTransferSize,
          placeholder: const Text('Usar padrão do SQL Server'),
          items: const [
            ComboBoxItem(child: Text('Usar padrão')),
            ComboBoxItem(value: 4194304, child: Text('4 MB')),
            ComboBoxItem(value: 16777216, child: Text('16 MB')),
            ComboBoxItem(value: 67108864, child: Text('64 MB')),
          ],
          onChanged: (value) {
            final newValue = value ?? 4194304;
            setState(() {
              _maxTransferSize = newValue;
            });
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Tamanho máximo de transferência em bytes. Múltiplo de 64KB.',
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        AppDropdown<int?>(
          label: 'Buffer Count (BUFFERCOUNT)',
          value: _bufferCount,
          placeholder: const Text('Usar padrão do SQL Server'),
          items: const [
            ComboBoxItem(child: Text('Usar padrão')),
            ComboBoxItem(value: 50, child: Text('50')),
            ComboBoxItem(value: 100, child: Text('100')),
            ComboBoxItem(value: 200, child: Text('200')),
          ],
          onChanged: (value) {
            final newValue = value ?? 10;
            setState(() {
              _bufferCount = newValue;
            });
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Número de buffers de I/O. Valores altos podem causar consumo excessivo de memória.',
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        AppDropdown<int>(
          label: 'STATS Percentual',
          value: _statsPercent,
          placeholder: const Text('10%'),
          items: const [
            ComboBoxItem<int>(value: 1, child: Text('1%')),
            ComboBoxItem<int>(value: 5, child: Text('5%')),
            ComboBoxItem<int>(value: 10, child: Text('10%')),
          ],
          onChanged: (value) {
            final newValue = value ?? 10;
            setState(() {
              _statsPercent = newValue;
            });
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Porcentagem de progresso para exibir. O SQL Server relata progresso a cada X%.',
          style: FluentTheme.of(context).typography.caption,
        ),
      ],
    );
  }

  Widget _buildIntegrityOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('Verificação de Integridade'),
        const SizedBox(height: 12),
        if (_databaseType == DatabaseType.sqlServer)
          Consumer<LicenseProvider>(
            builder: (context, licenseProvider, child) {
              final hasChecksum =
                  licenseProvider.hasValidLicense &&
                  licenseProvider.currentLicense!.hasFeature(
                    LicenseFeatures.checksum,
                  );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildCheckboxWithInfo(
                          label: hasChecksum
                              ? 'Enable CheckSum'
                              : 'Enable CheckSum (Requer licença)',
                          value: _enableChecksum,
                          onChanged: hasChecksum
                              ? (value) {
                                  setState(() {
                                    _enableChecksum = value;
                                  });
                                }
                              : null,
                          infoText: hasChecksum
                              ? 'Habilita o cálculo de checksums durante o backup. '
                                    'Detecta corrupção de dados durante o processo de backup.'
                              : 'Este recurso requer uma licença válida. '
                                    'Acesse Configurações > Licenciamento para mais informações.',
                        ),
                      ),
                      if (!hasChecksum) ...[
                        const SizedBox(width: 8),
                        Icon(
                          FluentIcons.lock,
                          size: 16,
                          color: FluentTheme.of(context)
                              .resources
                              .controlStrokeColorDefault
                              .withValues(alpha: 0.4),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        Consumer<LicenseProvider>(
          builder: (context, licenseProvider, child) {
            final hasVerifyIntegrity =
                licenseProvider.hasValidLicense &&
                licenseProvider.currentLicense!.hasFeature(
                  LicenseFeatures.verifyIntegrity,
                );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildCheckboxWithInfo(
                        label: hasVerifyIntegrity
                            ? 'Verify After Backup'
                            : 'Verify After Backup (Requer licença)',
                        value: _verifyAfterBackup,
                        onChanged: hasVerifyIntegrity
                            ? (value) {
                                setState(() {
                                  _verifyAfterBackup = value;
                                });
                              }
                            : null,
                        infoText: hasVerifyIntegrity
                            ? (_databaseType == DatabaseType.sqlServer
                                  ? 'Verifica a integridade do backup após criação usando RESTORE VERIFYONLY. '
                                        'Garante que o backup pode ser restaurado sem restaurar os dados.'
                                  : _databaseType == DatabaseType.postgresql
                                  ? 'Verifica a integridade do backup após criação usando pg_verifybackup. '
                                        'Garante que o backup está íntegro e pode ser restaurado.'
                                  : 'Verifica a integridade do backup após criação usando dbvalid (preferencial) '
                                        'e dbverify (fallback). Garante que o backup está íntegro e pode ser restaurado.')
                            : 'Este recurso requer uma licença válida. '
                                  'Acesse Configurações > Licenciamento para mais informações.',
                      ),
                    ),
                    if (!hasVerifyIntegrity) ...[
                      const SizedBox(width: 8),
                      Icon(
                        FluentIcons.lock,
                        size: 16,
                        color: FluentTheme.of(context)
                            .resources
                            .controlStrokeColorDefault
                            .withValues(alpha: 0.4),
                      ),
                    ],
                  ],
                ),
                if (_verifyAfterBackup) ...[
                  const SizedBox(height: 16),
                  AppDropdown<VerifyPolicy>(
                    label: 'Política de Verificação',
                    value: _verifyPolicy,
                    placeholder: const Text('Política de Verificação'),
                    items: const [
                      ComboBoxItem<VerifyPolicy>(
                        value: VerifyPolicy.bestEffort,
                        child: Text('Melhor Esforço (Best Effort)'),
                      ),
                      ComboBoxItem<VerifyPolicy>(
                        value: VerifyPolicy.strict,
                        child: Text('Estrito (Strict)'),
                      ),
                      ComboBoxItem<VerifyPolicy>(
                        value: VerifyPolicy.none,
                        child: Text('Nenhum (None)'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _verifyPolicy = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getVerifyPolicyDescription(_verifyPolicy),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  String _getVerifyPolicyDescription(VerifyPolicy policy) {
    switch (policy) {
      case VerifyPolicy.bestEffort:
        return 'Verifica a integridade do backup, mas continua mesmo em caso de falha na verificação.';
      case VerifyPolicy.strict:
        return 'Verifica a integridade do backup. Se a verificação falhar, o backup é considerado falho.';
      case VerifyPolicy.none:
        return 'Não realiza verificação de integridade do backup.';
    }
  }

  Widget _buildCheckboxWithInfo({
    required String label,
    required bool value,
    required String infoText,
    ValueChanged<bool>? onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InfoLabel(
            label: label,
            child: Checkbox(
              checked: value,
              onChanged: onChanged != null
                  ? (checked) => onChanged(checked ?? false)
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Tooltip(
            message: infoText,
            child: IconButton(
              icon: const Icon(FluentIcons.info, size: 16),
              onPressed: () {},
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScriptTab() {
    return Consumer<LicenseProvider>(
      builder: (context, licenseProvider, child) {
        final hasPostScript =
            licenseProvider.hasValidLicense &&
            licenseProvider.currentLicense!.hasFeature(
              LicenseFeatures.postBackupScript,
            );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionTitle('Script SQL Pós-Backup (Opcional)'),
              const SizedBox(height: 16),
              if (!hasPostScript)
                const InfoBar(
                  severity: InfoBarSeverity.warning,
                  title: Text('Recurso Bloqueado'),
                  content: Text(
                    'Este recurso requer uma licença válida com permissão para scripts SQL pós-backup.',
                  ),
                ),
              if (!hasPostScript) const SizedBox(height: 16),
              InfoLabel(
                label: 'Script SQL',
                child: TextBox(
                  controller: _postBackupScriptController,
                  placeholder:
                      "Ex: UPDATE tabela SET status = 'backup_completo' WHERE id = 1;",
                  maxLines: 15,
                  minLines: 10,
                  readOnly: !hasPostScript,
                ),
              ),
              const SizedBox(height: 16),
              const InfoBar(
                title: Text('Informação'),
                content: Text(
                  'O script será executado na mesma conexão do backup, '
                  'após o backup ser concluído com sucesso. '
                  'Erros no script não impedem o backup de ser considerado bem-sucedido.',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: FluentTheme.of(
        context,
      ).typography.subtitle?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildDatabaseConfigDropdown() {
    if (_databaseType == DatabaseType.sqlServer) {
      return Consumer<SqlServerConfigProvider>(
        builder: (context, provider, child) {
          final sqlServerItems = provider.configs.map((config) {
            return ComboBoxItem<String>(
              value: config.id,
              child: Text(
                '${config.name} (${config.server}:${config.database})',
              ),
            );
          }).toList();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                _sqlServerConfigs.length != provider.configs.length) {
              setState(() {
                _sqlServerConfigs = provider.configs;
              });
            }
          });

          String? validValue;
          if (_selectedDatabaseConfigId != null) {
            final exists = sqlServerItems.any(
              (item) => item.value == _selectedDatabaseConfigId,
            );
            validValue = exists ? _selectedDatabaseConfigId : null;
            if (!exists) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _selectedDatabaseConfigId = null;
                  });
                }
              });
            }
          } else {
            validValue = null;
          }

          return AppDropdown<String>(
            label: 'Configuração de Banco',
            value: validValue,
            placeholder: Text(
              sqlServerItems.isEmpty
                  ? 'Nenhuma configuração disponível'
                  : 'Selecione uma configuração',
            ),
            items: sqlServerItems.isEmpty
                ? [
                    ComboBoxItem<String>(
                      child: Text(
                        'Nenhuma configuração disponível',
                        style: FluentTheme.of(context).typography.caption
                            ?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ),
                  ]
                : sqlServerItems,
            onChanged: sqlServerItems.isEmpty
                ? null
                : (value) {
                    setState(() {
                      _selectedDatabaseConfigId = value;
                    });
                  },
          );
        },
      );
    }

    if (_databaseType == DatabaseType.postgresql) {
      return Consumer<PostgresConfigProvider>(
        builder: (context, provider, child) {
          final postgresItems = provider.configs.map((config) {
            return ComboBoxItem<String>(
              value: config.id,
              child: Text(
                '${config.name} (${config.host}:${config.port}/${config.database})',
              ),
            );
          }).toList();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _postgresConfigs.length != provider.configs.length) {
              setState(() {
                _postgresConfigs = provider.configs;
              });
            }
          });

          String? validValue;
          if (_selectedDatabaseConfigId != null) {
            final exists = postgresItems.any(
              (item) => item.value == _selectedDatabaseConfigId,
            );
            validValue = exists ? _selectedDatabaseConfigId : null;
            if (!exists) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _selectedDatabaseConfigId = null;
                  });
                }
              });
            }
          } else {
            validValue = null;
          }

          return AppDropdown<String>(
            label: 'Configuração de Banco',
            value: validValue,
            placeholder: Text(
              postgresItems.isEmpty
                  ? 'Nenhuma configuração disponível'
                  : 'Selecione uma configuração',
            ),
            items: postgresItems.isEmpty
                ? [
                    ComboBoxItem<String>(
                      child: Text(
                        'Nenhuma configuração disponível',
                        style: FluentTheme.of(context).typography.caption
                            ?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ),
                  ]
                : postgresItems,
            onChanged: postgresItems.isEmpty
                ? null
                : (value) {
                    setState(() {
                      _selectedDatabaseConfigId = value;
                    });
                  },
          );
        },
      );
    }

    return Consumer<SybaseConfigProvider>(
      builder: (context, provider, child) {
        final sybaseItems = provider.configs.map((config) {
          return ComboBoxItem<String>(
            value: config.id,
            child: Text('${config.name} (${config.serverName}:${config.port})'),
          );
        }).toList();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _sybaseConfigs.length != provider.configs.length) {
            setState(() {
              _sybaseConfigs = provider.configs;
            });
          }
        });

        String? validValue;
        if (_selectedDatabaseConfigId != null) {
          final exists = sybaseItems.any(
            (item) => item.value == _selectedDatabaseConfigId,
          );
          validValue = exists ? _selectedDatabaseConfigId : null;
          if (!exists) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _selectedDatabaseConfigId = null;
                });
              }
            });
          }
        } else {
          validValue = null;
        }

        return AppDropdown<String>(
          label: 'Configuração de Banco',
          value: validValue,
          placeholder: Text(
            sybaseItems.isEmpty
                ? 'Nenhuma configuração disponível'
                : 'Selecione uma configuração',
          ),
          items: sybaseItems.isEmpty
              ? [
                  ComboBoxItem<String>(
                    child: Text(
                      'Nenhuma configuração disponível',
                      style: FluentTheme.of(context).typography.caption
                          ?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ),
                ]
              : sybaseItems,
          onChanged: sybaseItems.isEmpty
              ? null
              : (value) {
                  setState(() {
                    _selectedDatabaseConfigId = value;
                  });
                },
        );
      },
    );
  }

  Widget _buildScheduleFields() {
    switch (_scheduleType) {
      case ScheduleType.daily:
        return _buildTimeSelector();
      case ScheduleType.weekly:
        return Column(
          children: [
            _buildDayOfWeekSelector(),
            const SizedBox(height: 16),
            _buildTimeSelector(),
          ],
        );
      case ScheduleType.monthly:
        return Column(
          children: [
            _buildDayOfMonthSelector(),
            const SizedBox(height: 16),
            _buildTimeSelector(),
          ],
        );
      case ScheduleType.interval:
        return _buildIntervalSelector();
    }
  }

  Widget _buildTimeSelector() {
    return Row(
      children: [
        Expanded(
          child: AppDropdown<int>(
            label: 'Hora',
            value: _hour,
            placeholder: const Text('Hora'),
            items: List.generate(24, (index) {
              return ComboBoxItem<int>(
                value: index,
                child: Text(index.toString().padLeft(2, '0')),
              );
            }),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _hour = value;
                });
              }
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: AppDropdown<int>(
            label: 'Minuto',
            value: _minute,
            placeholder: const Text('Minuto'),
            items: List.generate(60, (index) {
              return ComboBoxItem<int>(
                value: index,
                child: Text(index.toString().padLeft(2, '0')),
              );
            }),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _minute = value;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDayOfWeekSelector() {
    final days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

    return Wrap(
      spacing: 8,
      children: List.generate(7, (index) {
        final dayNumber = index + 1;
        final isSelected = _selectedDaysOfWeek.contains(dayNumber);

        return Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: Checkbox(
            checked: isSelected,
            onChanged: (value) {
              setState(() {
                if (value ?? false) {
                  _selectedDaysOfWeek.add(dayNumber);
                } else if (_selectedDaysOfWeek.length > 1) {
                  _selectedDaysOfWeek.remove(dayNumber);
                }
                _selectedDaysOfWeek.sort();
              });
            },
            content: Text(days[index]),
          ),
        );
      }),
    );
  }

  Widget _buildDayOfMonthSelector() {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: List.generate(31, (index) {
        final day = index + 1;
        final isSelected = _selectedDaysOfMonth.contains(day);

        return Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 4),
          child: Checkbox(
            checked: isSelected,
            onChanged: (value) {
              setState(() {
                if (value ?? false) {
                  _selectedDaysOfMonth.add(day);
                } else if (_selectedDaysOfMonth.length > 1) {
                  _selectedDaysOfMonth.remove(day);
                }
                _selectedDaysOfMonth.sort();
              });
            },
            content: Text(day.toString()),
          ),
        );
      }),
    );
  }

  Widget _buildIntervalSelector() {
    return NumericField(
      controller: _intervalMinutesController,
      label: 'Intervalo (minutos)',
      hint: 'Ex: 60 para cada hora',
      prefixIcon: FluentIcons.timer,
      minValue: 1,
      onChanged: (value) {
        final minutes = int.tryParse(value) ?? 60;
        setState(() {
          _intervalMinutes = minutes;
        });
      },
    );
  }

  Widget _buildDestinationSelector() {
    if (_destinations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.errorBackground.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(FluentIcons.warning, color: AppColors.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Nenhum destino configurado. Configure um destino primeiro.',
                style: FluentTheme.of(
                  context,
                ).typography.caption?.copyWith(color: AppColors.error),
              ),
            ),
          ],
        ),
      );
    }

    return Consumer<LicenseProvider>(
      builder: (context, licenseProvider, _) {
        final hasGoogleDrive =
            licenseProvider.hasValidLicense &&
            licenseProvider.currentLicense!.hasFeature(
              LicenseFeatures.googleDrive,
            );
        final hasDropbox =
            licenseProvider.hasValidLicense &&
            licenseProvider.currentLicense!.hasFeature(LicenseFeatures.dropbox);
        final hasNextcloud =
            licenseProvider.hasValidLicense &&
            licenseProvider.currentLicense!.hasFeature(
              LicenseFeatures.nextcloud,
            );

        bool isBlocked(DestinationType type) {
          if (type == DestinationType.googleDrive) return !hasGoogleDrive;
          if (type == DestinationType.dropbox) return !hasDropbox;
          if (type == DestinationType.nextcloud) return !hasNextcloud;
          return false;
        }

        return Column(
          children: _destinations.map((destination) {
            final selected = _selectedDestinationIds.contains(destination.id);
            final blocked = isBlocked(destination.type);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(_getDestinationIcon(destination.type), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          destination.name,
                          style: FluentTheme.of(context).typography.body,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                blocked
                                    ? '${_getDestinationTypeName(destination.type)} (Requer licença)'
                                    : _getDestinationTypeName(destination.type),
                                style: FluentTheme.of(context)
                                    .typography
                                    .caption
                                    ?.copyWith(
                                      color: blocked
                                          ? FluentTheme.of(context)
                                                .resources
                                                .controlStrokeColorDefault
                                                .withValues(alpha: 0.6)
                                          : null,
                                    ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (blocked) ...[
                              const SizedBox(width: 8),
                              Icon(
                                FluentIcons.lock,
                                size: 14,
                                color: FluentTheme.of(context)
                                    .resources
                                    .controlStrokeColorDefault
                                    .withValues(alpha: 0.6),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Checkbox(
                    checked: selected,
                    onChanged: (value) {
                      if ((value ?? false) && blocked) {
                        MessageModal.showWarning(
                          context,
                          message:
                              'Este destino requer uma licença válida. '
                              'Acesse Configurações > Licenciamento para mais informações.',
                        );
                        return;
                      }
                      setState(() {
                        if (value ?? false) {
                          _selectedDestinationIds.add(destination.id);
                        } else {
                          _selectedDestinationIds.remove(destination.id);
                        }
                      });
                    },
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  String _getDatabaseTypeName(DatabaseType type) {
    switch (type) {
      case DatabaseType.sqlServer:
        return 'SQL Server';
      case DatabaseType.sybase:
        return 'Sybase SQL Anywhere';
      case DatabaseType.postgresql:
        return 'PostgreSQL';
    }
  }

  String _getScheduleTypeName(ScheduleType type) {
    switch (type) {
      case ScheduleType.daily:
        return 'Diário';
      case ScheduleType.weekly:
        return 'Semanal';
      case ScheduleType.monthly:
        return 'Mensal';
      case ScheduleType.interval:
        return 'Por Intervalo';
    }
  }

  String _getBackupTypeDescription(BackupType type) {
    if (_databaseType == DatabaseType.postgresql) {
      switch (type) {
        case BackupType.full:
          return 'Backup físico completo usando pg_basebackup. Banco ONLINE. Inclui todos os bancos do cluster, dados, estrutura e catálogo.';
        case BackupType.fullSingle:
          return 'Backup lógico completo usando pg_dump. Banco ONLINE. Inclui apenas a base de dados especificada na configuração. Formato .backup.';
        case BackupType.log:
        case BackupType.convertedLog:
          return 'Captura de WAL para PITR usando pg_receivewal em modo one-shot (ate um LSN alvo). Pode usar replication slot dedicado quando habilitado por ambiente.';
        case BackupType.differential:
        case BackupType.convertedDifferential:
          return 'Backup incremental usando pg_basebackup. Requer backup FULL anterior com manifest. (PostgreSQL 17+)';
        case BackupType.convertedFullSingle:
          return 'Backup lógico completo usando pg_dump. Banco ONLINE. Inclui apenas a base de dados especificada na configuração. Formato .backup.';
      }
    }
    if (_databaseType == DatabaseType.sybase) {
      switch (type) {
        case BackupType.full:
          return 'Backup completo do banco de dados via BACKUP DATABASE/dbbackup.';
        case BackupType.log:
        case BackupType.convertedLog:
          return 'Backup do log de transações. Pode ser executado frequentemente e requer backup Full anterior.';
        case BackupType.differential:
        case BackupType.convertedDifferential:
          return 'Sybase SQL Anywhere não suporta backup diferencial nativo; este tipo é convertido automaticamente para Full.';
        case BackupType.fullSingle:
        case BackupType.convertedFullSingle:
          return 'Sybase trata este tipo como backup Full.';
      }
    }
    switch (type) {
      case BackupType.full:
        return 'Backup completo do banco de dados. Base para backups diferenciais e logs.';
      case BackupType.fullSingle:
        return 'Backup completo de uma base de dados específica.';
      case BackupType.differential:
        return 'Backup apenas das alterações desde o último backup completo. Requer backup Full anterior.';
      case BackupType.log:
        return 'Backup do log de transações. Pode ser executado frequentemente. Requer backup Full anterior.';
      case BackupType.convertedDifferential:
        return 'Backup convertido de Differential para Full.';
      case BackupType.convertedFullSingle:
        return 'Backup convertido de Full Single para Full.';
      case BackupType.convertedLog:
        return 'Backup convertido de Log para Log.';
    }
  }

  String _getDestinationTypeName(DestinationType type) {
    switch (type) {
      case DestinationType.local:
        return 'Pasta Local';
      case DestinationType.ftp:
        return 'Servidor FTP';
      case DestinationType.googleDrive:
        return 'Google Drive';
      case DestinationType.dropbox:
        return 'Dropbox';
      case DestinationType.nextcloud:
        return 'Nextcloud';
    }
  }

  IconData _getDestinationIcon(DestinationType type) {
    switch (type) {
      case DestinationType.local:
        return FluentIcons.folder;
      case DestinationType.ftp:
        return FluentIcons.cloud_upload;
      case DestinationType.googleDrive:
        return FluentIcons.cloud;
      case DestinationType.dropbox:
        return FluentIcons.cloud;
      case DestinationType.nextcloud:
        return FluentIcons.cloud;
    }
  }

  Future<void> _selectBackupFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Selecionar pasta de backup',
    );
    if (result != null) {
      setState(() {
        _backupFolderController.text = result;
      });
    }
  }

  Future<bool> _validateBackupFolder() async {
    final path = _backupFolderController.text.trim();
    if (path.isEmpty) {
      MessageModal.showWarning(
        context,
        message: 'Pasta de backup é obrigatória',
      );
      return false;
    }

    final directory = Directory(path);
    if (!await directory.exists()) {
      if (!mounted) return false;
      final shouldCreate = await showDialog<bool>(
        context: context,
        builder: (context) => ContentDialog(
          title: const Text('Pasta não existe'),
          content: Text('A pasta "$path" não existe. Deseja criá-la?'),
          actions: [
            Button(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Criar Pasta'),
            ),
          ],
        ),
      );

      if (shouldCreate ?? false) {
        try {
          await directory.create(recursive: true);
        } on Object catch (e, s) {
          LoggerService.warning('Erro ao criar pasta: ${directory.path}', e, s);
          if (mounted) {
            MessageModal.showError(
              context,
              message: 'Erro ao criar pasta: $e',
            );
          }
          return false;
        }
      } else {
        return false;
      }
    }

    final hasPermission = await _checkWritePermission(directory);
    if (!hasPermission) {
      if (mounted) {
        MessageModal.showError(
          context,
          message:
              'Sem permissão de escrita na pasta selecionada.\n'
              'Verifique as permissões do diretório.',
        );
      }
      return false;
    }

    return true;
  }

  Future<bool> _checkWritePermission(Directory directory) async {
    try {
      final testFileName =
          '.backup_permission_test_${DateTime.now().millisecondsSinceEpoch}';
      final testFile = File(
        '${directory.path}${Platform.pathSeparator}$testFileName',
      );

      await testFile.writeAsString('test');

      if (await testFile.exists()) {
        await testFile.delete();
        return true;
      }

      return false;
    } on Object catch (e) {
      LoggerService.warning(
        'Erro ao verificar permissão de escrita na pasta ${directory.path}: $e',
      );
      return false;
    }
  }

  Future<bool> _checkWinRarAvailable() async {
    final possiblePaths = [
      r'C:\Program Files\WinRAR\WinRAR.exe',
      r'C:\Program Files (x86)\WinRAR\WinRAR.exe',
    ];

    for (final path in possiblePaths) {
      final file = File(path);
      if (await file.exists()) {
        return true;
      }
    }

    return false;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _selectedTabIndex = 0;
        _nameFieldTouched = true;
      });
      _formKey.currentState?.validate();
      MessageModal.showWarning(
        context,
        message: 'Nome do agendamento é obrigatório',
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      setState(() {
        _nameFieldTouched = true;
      });
      return;
    }

    if (_selectedDatabaseConfigId == null) {
      MessageModal.showWarning(
        context,
        message: 'Selecione uma configuração de banco de dados',
      );
      return;
    }

    if (_selectedDestinationIds.isEmpty) {
      MessageModal.showWarning(
        context,
        message: 'Selecione pelo menos um destino',
      );
      return;
    }

    await _loadData();
    if (!mounted) return;

    final configExists = _databaseType == DatabaseType.sqlServer
        ? _sqlServerConfigs.any((c) => c.id == _selectedDatabaseConfigId)
        : _databaseType == DatabaseType.sybase
        ? _sybaseConfigs.any((c) => c.id == _selectedDatabaseConfigId)
        : _postgresConfigs.any((c) => c.id == _selectedDatabaseConfigId);

    if (!configExists) {
      MessageModal.showError(
        context,
        message:
            'A configuração de banco selecionada não existe mais. '
            'Por favor, selecione outra configuração.',
      );
      return;
    }

    if (_compressBackup && _compressionFormat == CompressionFormat.rar) {
      final winRarAvailable = await _checkWinRarAvailable();
      if (!winRarAvailable) {
        if (mounted) {
          MessageModal.showError(
            context,
            message:
                'Formato RAR requer WinRAR instalado.\n\n'
                'WinRAR não foi encontrado no sistema.\n'
                'Por favor, instale o WinRAR ou escolha o formato ZIP.',
          );
        }
        return;
      }
    }

    final effectiveCompressionFormat = _compressBackup
        ? _compressionFormat
        : CompressionFormat.none;
    final effectiveBackupType = _normalizeBackupTypeForDatabase(
      _databaseType,
      _backupType,
    );

    final isValidFolder = await _validateBackupFolder();
    if (!isValidFolder) {
      return;
    }

    if (!mounted) return;

    final licenseProvider = Provider.of<LicenseProvider>(
      context,
      listen: false,
    );
    final hasChecksum =
        licenseProvider.hasValidLicense &&
        licenseProvider.currentLicense!.hasFeature(LicenseFeatures.checksum);

    final effectiveEnableChecksum =
        _databaseType == DatabaseType.sqlServer &&
        (hasChecksum && _enableChecksum);

    String scheduleConfigJson;
    switch (_scheduleType) {
      case ScheduleType.daily:
        scheduleConfigJson = jsonEncode({'hour': _hour, 'minute': _minute});
      case ScheduleType.weekly:
        scheduleConfigJson = jsonEncode({
          'daysOfWeek': _selectedDaysOfWeek,
          'hour': _hour,
          'minute': _minute,
        });
      case ScheduleType.monthly:
        scheduleConfigJson = jsonEncode({
          'daysOfMonth': _selectedDaysOfMonth,
          'hour': _hour,
          'minute': _minute,
        });
      case ScheduleType.interval:
        scheduleConfigJson = jsonEncode({'intervalMinutes': _intervalMinutes});
    }

    final scheduleTypeString = _scheduleType.toValue();

    final sqlServerBackupOptions = SqlServerBackupOptions(
      compression: _compression,
      maxTransferSize: _maxTransferSize,
      bufferCount: _bufferCount,
      blockSize: _blockSize,
      stripingCount: _stripingCount,
      statsPercent: _statsPercent,
    );

    final Schedule schedule;
    if (_databaseType == DatabaseType.sqlServer) {
      schedule = SqlServerBackupSchedule(
        id: widget.schedule?.id,
        name: _nameController.text.trim(),
        databaseConfigId: _selectedDatabaseConfigId!,
        databaseType: _databaseType,
        scheduleType: scheduleTypeString,
        scheduleConfig: scheduleConfigJson,
        destinationIds: _selectedDestinationIds,
        backupFolder: _backupFolderController.text.trim(),
        backupType: effectiveBackupType,
        compressBackup: _compressBackup,
        compressionFormat: effectiveCompressionFormat,
        enabled: _isEnabled,
        enableChecksum: effectiveEnableChecksum,
        verifyAfterBackup: _verifyAfterBackup,
        verifyPolicy: _verifyPolicy,
        postBackupScript: _postBackupScriptController.text.trim().isEmpty
            ? null
            : _postBackupScriptController.text.trim(),
        lastRunAt: widget.schedule?.lastRunAt,
        nextRunAt: widget.schedule?.nextRunAt,
        createdAt: widget.schedule?.createdAt,
        truncateLog: _truncateLog,
        backupTimeout: _backupTimeout,
        verifyTimeout: _verifyTimeout,
        sqlServerBackupOptions: sqlServerBackupOptions,
        isConvertedDifferential:
            widget.schedule?.isConvertedDifferential ?? false,
      );
    } else {
      schedule = Schedule(
        id: widget.schedule?.id,
        name: _nameController.text.trim(),
        databaseConfigId: _selectedDatabaseConfigId!,
        databaseType: _databaseType,
        scheduleType: scheduleTypeString,
        scheduleConfig: scheduleConfigJson,
        destinationIds: _selectedDestinationIds,
        backupFolder: _backupFolderController.text.trim(),
        backupType: effectiveBackupType,
        compressBackup: _compressBackup,
        compressionFormat: effectiveCompressionFormat,
        enabled: _isEnabled,
        enableChecksum: effectiveEnableChecksum,
        verifyAfterBackup: _verifyAfterBackup,
        verifyPolicy: _verifyPolicy,
        postBackupScript: _postBackupScriptController.text.trim().isEmpty
            ? null
            : _postBackupScriptController.text.trim(),
        lastRunAt: widget.schedule?.lastRunAt,
        nextRunAt: widget.schedule?.nextRunAt,
        createdAt: widget.schedule?.createdAt,
        truncateLog: _truncateLog,
        backupTimeout: _backupTimeout,
        verifyTimeout: _verifyTimeout,
        isConvertedDifferential:
            _databaseType == DatabaseType.sybase &&
            _backupType == BackupType.differential,
      );
    }

    if (mounted) {
      Navigator.of(context).pop(schedule);
    }
  }
}
