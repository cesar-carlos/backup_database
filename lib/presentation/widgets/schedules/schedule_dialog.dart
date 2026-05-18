import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/schedule_dialog_strings.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/utils/directory_permission_check.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/infrastructure/external/compression/winrar_service.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_advanced_database_section.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_firebird_nbackup_section.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_general_section.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_schedule_section.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_script_tab.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_settings_tab.dart';
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
  final _firebirdNbackupPhysicalLevelController = TextEditingController();

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

  SybaseCheckpointLog? _sybaseCheckpointLog;
  bool _sybaseServerSide = false;
  bool _sybaseAutoTuneWriters = false;
  int? _sybaseBlockSize;
  SybaseLogBackupMode? _sybaseLogBackupMode;

  int _hour = 0;
  int _minute = 0;
  List<int> _selectedDaysOfWeek = [1];
  List<int> _selectedDaysOfMonth = [1];
  int _intervalMinutes = 60;

  List<SqlServerConfig> _sqlServerConfigs = [];
  List<SybaseConfig> _sybaseConfigs = [];
  List<PostgresConfig> _postgresConfigs = [];
  List<FirebirdConfig> _firebirdConfigs = [];
  List<BackupDestination> _destinations = [];
  bool _isLoading = true;

  bool get isEditing => widget.schedule != null;

  bool get _hideRemoteFirebird {
    if (currentAppMode != AppMode.client) {
      return false;
    }
    try {
      final scp = context.watch<ServerConnectionProvider>();
      return scp.isConnected && !scp.isFirebirdSupported;
    } on ProviderNotFoundException {
      return false;
    }
  }

  List<DatabaseType> _databaseTypesForGeneralPicker() {
    if (!_hideRemoteFirebird) {
      return DatabaseType.values.toList();
    }
    final withoutFb = DatabaseType.values
        .where((DatabaseType t) => t != DatabaseType.firebird)
        .toList();
    final keepFirebird =
        widget.schedule?.databaseType == DatabaseType.firebird ||
        _databaseType == DatabaseType.firebird;
    if (!keepFirebird) {
      return withoutFb;
    }
    return <DatabaseType>[...withoutFb, DatabaseType.firebird];
  }

  BackupType _normalizeBackupTypeForDatabase(
    DatabaseType databaseType,
    BackupType backupType,
  ) {
    if (databaseType != DatabaseType.postgresql &&
        databaseType != DatabaseType.firebird &&
        backupType == BackupType.fullSingle) {
      return BackupType.full;
    }
    if (databaseType == DatabaseType.sybase &&
        backupType == BackupType.differential) {
      return BackupType.full;
    }
    if (databaseType == DatabaseType.firebird) {
      switch (backupType) {
        case BackupType.full:
        case BackupType.fullSingle:
          return backupType;
        case BackupType.convertedFullSingle:
          return BackupType.fullSingle;
        case BackupType.log:
        case BackupType.differential:
        case BackupType.convertedDifferential:
        case BackupType.convertedLog:
          return BackupType.full;
      }
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
      _compressionFormat = widget.schedule!.compressionFormat;
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

      switch (widget.schedule!.databaseType) {
        case DatabaseType.sqlServer:
          final sqlServerBackupOptions =
              widget.schedule!.resolvedSqlServerBackupOptions;
          _compression = sqlServerBackupOptions.compression;
          _maxTransferSize = sqlServerBackupOptions.maxTransferSize;
          _bufferCount = sqlServerBackupOptions.bufferCount;
          _blockSize = sqlServerBackupOptions.blockSize;
          _stripingCount = sqlServerBackupOptions.stripingCount;
          _statsPercent = sqlServerBackupOptions.statsPercent;
        case DatabaseType.sybase:
          final sybaseBackupOptions =
              widget.schedule!.resolvedSybaseBackupOptions;
          _sybaseCheckpointLog = sybaseBackupOptions.checkpointLog;
          _sybaseServerSide = sybaseBackupOptions.serverSide;
          _sybaseAutoTuneWriters = sybaseBackupOptions.autoTuneWriters;
          _sybaseBlockSize = sybaseBackupOptions.blockSize;
          _sybaseLogBackupMode =
              sybaseBackupOptions.logBackupMode ??
              (widget.schedule!.truncateLog
                  ? SybaseLogBackupMode.truncate
                  : SybaseLogBackupMode.only);
        case DatabaseType.postgresql:
        case DatabaseType.firebird:
          break;
      }

      _backupFolderController.text = widget.schedule!.backupFolder.isNotEmpty
          ? widget.schedule!.backupFolder
          : _getDefaultBackupFolder();
      _postBackupScriptController.text =
          widget.schedule!.postBackupScript ?? '';

      if (widget.schedule!.firebirdNbackupPhysicalLevel != null) {
        _firebirdNbackupPhysicalLevelController.text =
            '${widget.schedule!.firebirdNbackupPhysicalLevel}';
      }

      _parseScheduleConfig(widget.schedule!.scheduleConfig);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadData());
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
    final firebirdProvider = context.read<FirebirdConfigProvider>();
    final destinationProvider = context.read<DestinationProvider>();

    await Future.wait([
      sqlServerProvider.loadConfigs(),
      sybaseProvider.loadConfigs(),
      postgresProvider.loadConfigs(),
      firebirdProvider.loadConfigs(),
      destinationProvider.loadDestinations(),
    ]);

    if (mounted) {
      setState(() {
        _sqlServerConfigs = sqlServerProvider.configs;
        _sybaseConfigs = sybaseProvider.configs;
        _postgresConfigs = postgresProvider.configs;
        _firebirdConfigs = firebirdProvider.configs;
        _destinations = destinationProvider.destinations;

        if (_selectedDatabaseConfigId != null) {
          final exists = switch (_databaseType) {
            DatabaseType.sqlServer => _sqlServerConfigs.any(
              (c) => c.id == _selectedDatabaseConfigId,
            ),
            DatabaseType.sybase => _sybaseConfigs.any(
              (c) => c.id == _selectedDatabaseConfigId,
            ),
            DatabaseType.postgresql => _postgresConfigs.any(
              (c) => c.id == _selectedDatabaseConfigId,
            ),
            DatabaseType.firebird => _firebirdConfigs.any(
              (c) => c.id == _selectedDatabaseConfigId,
            ),
          };

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
    } else if (_databaseType == DatabaseType.sybase &&
        _sybaseLogBackupMode == null) {
      _sybaseLogBackupMode = _truncateLog
          ? SybaseLogBackupMode.truncate
          : SybaseLogBackupMode.only;
    }
  }

  int? _parseFirebirdNbackupLevelFromController() {
    final trimmed = _firebirdNbackupPhysicalLevelController.text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.parse(trimmed);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _intervalMinutesController.dispose();
    _backupFolderController.dispose();
    _postBackupScriptController.dispose();
    _backupTimeoutMinutesController.dispose();
    _verifyTimeoutMinutesController.dispose();
    _firebirdNbackupPhysicalLevelController.dispose();
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
                      body: ScheduleDialogScriptTab(
                        postBackupScriptController: _postBackupScriptController,
                      ),
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
          ScheduleDialogGeneralSection(
            formKey: _formKey,
            nameController: _nameController,
            nameFieldTouched: _nameFieldTouched,
            onNameFirstInteraction: () {
              setState(() {
                _nameFieldTouched = true;
              });
            },
            databaseTypesForPicker: _databaseTypesForGeneralPicker(),
            databaseType: _databaseType,
            onDatabaseTypeChanged: isEditing
                ? null
                : (DatabaseType value) {
                    setState(() {
                      _selectedDatabaseConfigId = null;
                      _databaseType = value;
                      _backupType = _normalizeBackupTypeForDatabase(
                        _databaseType,
                        _backupType,
                      );
                      _onBackupTypeChanged();
                    });
                  },
            databaseConfigDropdownKey: ValueKey<String>(
              'database_config_dropdown_${_databaseType}_${_selectedDatabaseConfigId ?? 'null'}',
            ),
            databaseConfigDropdownBuilder: (BuildContext context) =>
                _buildDatabaseConfigDropdown(),
            backupType: _backupType,
            isSybaseConvertedDifferential:
                _databaseType == DatabaseType.sybase &&
                isEditing &&
                (widget.schedule?.isConvertedDifferential ?? false),
            onBackupTypeCommitted: (BackupType value) {
              setState(() {
                _backupType = value;
                _onBackupTypeChanged();
              });
            },
          ),
          const SizedBox(height: 24),
          ScheduleDialogScheduleSection(
            scheduleType: _scheduleType,
            onScheduleTypeCommitted: (ScheduleType value) {
              setState(() {
                _scheduleType = value;
              });
            },
            backupType: _backupType,
            databaseType: _databaseType,
            truncateLog: _truncateLog,
            onTruncateLogChanged: (bool value) {
              setState(() {
                _truncateLog = value;
              });
            },
            sybaseLogModeSelector:
                _backupType == BackupType.log &&
                    _databaseType == DatabaseType.sybase
                ? _buildSybaseLogBackupModeSelector()
                : null,
            scheduleFields: _buildScheduleFields(),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return ScheduleDialogSettingsTab(
      destinationSelector: _buildDestinationSelector(),
      backupFolderController: _backupFolderController,
      onSelectBackupFolderPressed: () {
        unawaited(_selectBackupFolder());
      },
      compressBackup: _compressBackup,
      onCompressBackupChanged: (bool value) {
        setState(() {
          _compressBackup = value;
          if (!value) {
            _compressionFormat = CompressionFormat.none;
          } else if (_compressionFormat == CompressionFormat.none) {
            _compressionFormat = CompressionFormat.zip;
          }
        });
      },
      compressionFormat: _compressionFormat,
      onCompressionFormatChanged: (CompressionFormat value) {
        setState(() {
          _compressionFormat = value;
        });
      },
      schedulingEnabled: _isEnabled,
      onSchedulingEnabledChanged: (bool value) {
        setState(() {
          _isEnabled = value;
        });
      },
      backupTimeoutMinutesController: _backupTimeoutMinutesController,
      verifyTimeoutMinutesController: _verifyTimeoutMinutesController,
      onBackupTimeoutMinutesParsed: (int minutes) {
        setState(() {
          _backupTimeout = Duration(minutes: minutes);
        });
      },
      onVerifyTimeoutMinutesParsed: (int minutes) {
        setState(() {
          _verifyTimeout = Duration(minutes: minutes);
        });
      },
      databaseType: _databaseType,
      backupType: _backupType,
      enableChecksum: _enableChecksum,
      onEnableChecksumChanged: (bool value) {
        setState(() {
          _enableChecksum = value;
        });
      },
      verifyAfterBackup: _verifyAfterBackup,
      onVerifyAfterBackupChanged: (bool value) {
        setState(() {
          _verifyAfterBackup = value;
        });
      },
      verifyPolicy: _verifyPolicy,
      onVerifyPolicyChanged: (VerifyPolicy value) {
        setState(() {
          _verifyPolicy = value;
        });
      },
      sqlServerAdvancedBuilder: () =>
          ScheduleDialogSqlServerAdvancedPerformanceSection(
            compression: _compression,
            onCompressionChanged: (bool value) {
              setState(() {
                _compression = value;
              });
            },
            maxTransferSize: _maxTransferSize,
            onMaxTransferSizeChanged: (int value) {
              setState(() {
                _maxTransferSize = value;
              });
            },
            bufferCount: _bufferCount,
            onBufferCountChanged: (int value) {
              setState(() {
                _bufferCount = value;
              });
            },
            statsPercent: _statsPercent,
            onStatsPercentChanged: (int value) {
              setState(() {
                _statsPercent = value;
              });
            },
            stripingCount: _stripingCount,
            onStripingCountChanged: (int value) {
              setState(() {
                _stripingCount = value;
              });
            },
          ),
      sybaseAdvancedBuilder: () =>
          ScheduleDialogSybaseAdvancedPerformanceSection(
            checkpointLog: _sybaseCheckpointLog,
            onCheckpointLogChanged: (SybaseCheckpointLog? value) {
              setState(() {
                _sybaseCheckpointLog = value;
              });
            },
            serverSide: _sybaseServerSide,
            onServerSideChanged: (bool value) {
              setState(() {
                _sybaseServerSide = value;
              });
            },
            autoTuneWriters: _sybaseAutoTuneWriters,
            onAutoTuneWritersChanged: (bool value) {
              setState(() {
                _sybaseAutoTuneWriters = value;
              });
            },
            blockSize: _sybaseBlockSize,
            onBlockSizeChanged: (int? value) {
              setState(() {
                _sybaseBlockSize = value;
              });
            },
          ),
      firebirdAdvancedBuilder: () {
        FirebirdConfig? firebirdConfig;
        final configId = _selectedDatabaseConfigId;
        if (configId != null) {
          for (final c in _firebirdConfigs) {
            if (c.id == configId) {
              firebirdConfig = c;
              break;
            }
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScheduleDialogFirebirdAdvancedSummarySection(
              config: firebirdConfig,
            ),
            ScheduleDialogFirebirdNbackupLevelSection(
              levelController: _firebirdNbackupPhysicalLevelController,
            ),
          ],
        );
      },
    );
  }

  Widget _buildSybaseLogBackupModeSelector() {
    final effectiveMode =
        _sybaseLogBackupMode ??
        (_truncateLog
            ? SybaseLogBackupMode.truncate
            : SybaseLogBackupMode.only);
    return AppDropdown<SybaseLogBackupMode>(
      label: 'Modo de log após backup',
      value: effectiveMode,
      items: const [
        ComboBoxItem(
          value: SybaseLogBackupMode.truncate,
          child: Text('Truncar (liberar espaço)'),
        ),
        ComboBoxItem(
          value: SybaseLogBackupMode.only,
          child: Text('Apenas backup (sem alterar log)'),
        ),
        ComboBoxItem(
          value: SybaseLogBackupMode.rename,
          child: Text('Renomear (recomendado para replicação)'),
        ),
      ],
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _sybaseLogBackupMode = value;
            _truncateLog = value == SybaseLogBackupMode.truncate;
          });
        }
      },
    );
  }

  Widget _buildDatabaseConfigDropdown() {
    if (_databaseType == DatabaseType.firebird) {
      return Consumer<FirebirdConfigProvider>(
        builder: (context, provider, child) {
          final firebirdItems = provider.configs.map((config) {
            return ComboBoxItem<String>(
              value: config.id,
              child: Text(
                '${config.name} (${config.host}:${config.port}/'
                '${config.databaseFile})',
              ),
            );
          }).toList();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _firebirdConfigs.length != provider.configs.length) {
              setState(() {
                _firebirdConfigs = provider.configs;
              });
            }
          });

          String? validValue;
          if (_selectedDatabaseConfigId != null) {
            final exists = firebirdItems.any(
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
              firebirdItems.isEmpty
                  ? 'Nenhuma configuração disponível'
                  : 'Selecione uma configuração',
            ),
            items: firebirdItems.isEmpty
                ? [
                    ComboBoxItem<String>(
                      child: Text(
                        'Nenhuma configuração disponível',
                        style: FluentTheme.of(context).typography.caption
                            ?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ),
                  ]
                : firebirdItems,
            onChanged: firebirdItems.isEmpty
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
        final license = licenseProvider.currentLicense;
        final hasGoogleDrive =
            licenseProvider.hasValidLicense &&
            (license?.hasFeature(LicenseFeatures.googleDrive) ?? false);
        final hasDropbox =
            licenseProvider.hasValidLicense &&
            (license?.hasFeature(LicenseFeatures.dropbox) ?? false);
        final hasNextcloud =
            licenseProvider.hasValidLicense &&
            (license?.hasFeature(LicenseFeatures.nextcloud) ?? false);

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
                        unawaited(
                          FluentInfoBarFeedback.showWarning(
                            context,
                            message:
                                'Este destino requer uma licença válida. '
                                'Acesse Configurações > Licenciamento para mais informações.',
                          ),
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
      unawaited(
        FluentInfoBarFeedback.showWarning(
          context,
          message: 'Pasta de backup é obrigatória',
        ),
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
            unawaited(
              MessageModal.showError(
                context,
                message: 'Erro ao criar pasta: $e',
              ),
            );
          }
          return false;
        }
      } else {
        return false;
      }
    }

    final hasPermission = await DirectoryPermissionCheck.hasWritePermission(
      directory,
    );
    if (!hasPermission) {
      if (mounted) {
        unawaited(
          MessageModal.showError(
            context,
            message:
                'Sem permissão de escrita na pasta selecionada.\n'
                'Verifique as permissões do diretório.',
          ),
        );
      }
      return false;
    }

    return true;
  }

  /// Antes este método tinha probe inline de caminhos do WinRAR — quando
  /// o setup mudasse (ex.: novo path de instalação), seria necessário
  /// atualizar 2 lugares. Agora delega ao `WinRarService.isInstalledInSystem`,
  /// mantendo a lista canônica em uma única fonte.
  Future<bool> _checkWinRarAvailable() => WinRarService.isInstalledInSystem();

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _selectedTabIndex = 0;
        _nameFieldTouched = true;
      });
      _formKey.currentState?.validate();
      unawaited(
        FluentInfoBarFeedback.showWarning(
          context,
          message: 'Nome do agendamento é obrigatório',
        ),
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
      unawaited(
        FluentInfoBarFeedback.showWarning(
          context,
          message: 'Selecione uma configuração de banco de dados',
        ),
      );
      return;
    }

    if (_selectedDestinationIds.isEmpty) {
      unawaited(
        FluentInfoBarFeedback.showWarning(
          context,
          message: 'Selecione pelo menos um destino',
        ),
      );
      return;
    }

    await _loadData();
    if (!mounted) return;

    final configExists = switch (_databaseType) {
      DatabaseType.sqlServer => _sqlServerConfigs.any(
        (c) => c.id == _selectedDatabaseConfigId,
      ),
      DatabaseType.sybase => _sybaseConfigs.any(
        (c) => c.id == _selectedDatabaseConfigId,
      ),
      DatabaseType.postgresql => _postgresConfigs.any(
        (c) => c.id == _selectedDatabaseConfigId,
      ),
      DatabaseType.firebird => _firebirdConfigs.any(
        (c) => c.id == _selectedDatabaseConfigId,
      ),
    };

    if (!configExists) {
      unawaited(
        MessageModal.showError(
          context,
          message:
              'A configuração de banco selecionada não existe mais. '
              'Por favor, selecione outra configuração.',
        ),
      );
      return;
    }

    if (_compressBackup && _compressionFormat == CompressionFormat.rar) {
      final winRarAvailable = await _checkWinRarAvailable();
      if (!winRarAvailable) {
        if (mounted) {
          unawaited(
            MessageModal.showError(
              context,
              message:
                  'Formato RAR requer WinRAR instalado.\n\n'
                  'WinRAR não foi encontrado no sistema.\n'
                  'Por favor, instale o WinRAR ou escolha o formato ZIP.',
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    final effectiveCompressionFormat = _compressBackup
        ? _compressionFormat
        : CompressionFormat.none;
    final effectiveBackupType = _normalizeBackupTypeForDatabase(
      _databaseType,
      _backupType,
    );

    if (_databaseType == DatabaseType.firebird) {
      final t = _firebirdNbackupPhysicalLevelController.text.trim();
      if (t.isNotEmpty) {
        final v = int.tryParse(t);
        if (v == null || v < 0 || v > 9) {
          unawaited(
            FluentInfoBarFeedback.showWarning(
              context,
              message:
                  'Nivel nbackup: use um inteiro de 0 a 9 ou deixe vazio '
                  '(automatico).',
            ),
          );
          return;
        }
      }
    }

    final isValidFolder = await _validateBackupFolder();
    if (!isValidFolder) {
      return;
    }

    if (!mounted) return;

    if (_databaseType == DatabaseType.sybase) {
      final sybaseOptions = SybaseBackupOptions(
        checkpointLog: _sybaseCheckpointLog,
        serverSide: _sybaseServerSide,
        autoTuneWriters: _sybaseAutoTuneWriters,
        blockSize: _sybaseBlockSize,
      );
      final validation = sybaseOptions.validate();
      if (!validation.isValid) {
        unawaited(
          FluentInfoBarFeedback.showWarning(
            context,
            message: 'Opções Sybase inválidas: ${validation.errorMessage}',
          ),
        );
        return;
      }
    }

    final licenseProvider = Provider.of<LicenseProvider>(
      context,
      listen: false,
    );
    final license = licenseProvider.currentLicense;
    final hasChecksum =
        licenseProvider.hasValidLicense &&
        (license?.hasFeature(LicenseFeatures.checksum) ?? false);

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
        sqlServerBackupOptions: sqlServerBackupOptions,
        isConvertedDifferential:
            widget.schedule?.isConvertedDifferential ?? false,
      );
    } else if (_databaseType == DatabaseType.sybase) {
      final effectiveLogMode =
          _sybaseLogBackupMode ??
          (_truncateLog
              ? SybaseLogBackupMode.truncate
              : SybaseLogBackupMode.only);
      final sybaseBackupOptions = SybaseBackupOptions(
        checkpointLog: _sybaseCheckpointLog,
        serverSide: _sybaseServerSide,
        autoTuneWriters: _sybaseAutoTuneWriters,
        blockSize: _sybaseBlockSize,
        logBackupMode: effectiveLogMode,
      );
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
        truncateLog: effectiveLogMode == SybaseLogBackupMode.truncate,
        backupTimeout: _backupTimeout,
        verifyTimeout: _verifyTimeout,
        sybaseBackupOptions: sybaseBackupOptions,
        isConvertedDifferential:
            widget.schedule?.isConvertedDifferential ??
            (_backupType == BackupType.differential),
      );
    } else {
      final firebirdNbackupPhysicalLevel =
          _databaseType == DatabaseType.firebird
          ? _parseFirebirdNbackupLevelFromController()
          : null;
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
        firebirdNbackupPhysicalLevel: firebirdNbackupPhysicalLevel,
      );
    }

    if (mounted) {
      Navigator.of(context).pop(schedule);
    }
  }
}
