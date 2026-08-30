import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/schedule_dialog_strings.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/utils/directory_permission_check.dart';
import 'package:backup_database/core/utils/winrar_install_probe.dart';
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
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_advanced_database_section.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_backup_type_rules.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_database_config_dropdown.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_destination_selector.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_draft.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_firebird_nbackup_section.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_general_section.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_schedule_fields.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_schedule_section.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_script_tab.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_settings_tab.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_sybase_log_mode.dart';
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
      _backupType = normalizeBackupTypeForDatabase(
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
    return AppDialogShell(
      constraints: const BoxConstraints(
        minWidth: 550,
        maxWidth: 650,
        maxHeight: 750,
      ),
      scrollable: false,
      title: Row(
        children: [
          const Icon(
            FluentIcons.calendar,
            color: AppPalette.scheduleDaily,
          ),
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
      onSubmitIntent: () {
        unawaited(_save());
      },
    );
  }

  Widget _buildGeneralTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Consumer<LicenseProvider>(
            builder: (context, licenseProvider, _) {
              if (!licenseProvider.isLicenseLoaded) {
                return const SizedBox.shrink();
              }
              final destinations = context
                  .read<DestinationProvider>()
                  .destinations;
              final selectedDestinations = destinations
                  .where((d) => _selectedDestinationIds.contains(d.id))
                  .toList();
              final lockedType =
                  (_backupType == BackupType.differential ||
                      _backupType == BackupType.convertedDifferential) &&
                  !licenseProvider.isFeatureUnlocked(
                    LicenseFeatures.differentialBackup,
                  );
              final lockedLog =
                  (_backupType == BackupType.log ||
                      _backupType == BackupType.convertedLog) &&
                  !licenseProvider.isFeatureUnlocked(LicenseFeatures.logBackup);
              final lockedInterval =
                  _scheduleType == ScheduleType.interval &&
                  !licenseProvider.isFeatureUnlocked(
                    LicenseFeatures.intervalSchedule,
                  );
              final lockedChecksum =
                  _enableChecksum &&
                  !licenseProvider.isFeatureUnlocked(LicenseFeatures.checksum);
              final lockedVerify =
                  _verifyAfterBackup &&
                  !licenseProvider.isFeatureUnlocked(
                    LicenseFeatures.verifyIntegrity,
                  );
              final lockedScript =
                  _postBackupScriptController.text.trim().isNotEmpty &&
                  !licenseProvider.isFeatureUnlocked(
                    LicenseFeatures.postBackupScript,
                  );
              final lockedDest = selectedDestinations.any(
                licenseProvider.destinationUsesLockedPremium,
              );
              if (!lockedType &&
                  !lockedLog &&
                  !lockedInterval &&
                  !lockedChecksum &&
                  !lockedVerify &&
                  !lockedScript &&
                  !lockedDest) {
                return const SizedBox.shrink();
              }
              return const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: LicensePremiumInactiveInfoBar(),
              );
            },
          ),
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
                      _backupType = normalizeBackupTypeForDatabase(
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
                ScheduleDialogDatabaseConfigDropdown(
                  databaseType: _databaseType,
                  selectedConfigId: _selectedDatabaseConfigId,
                  sqlServerConfigsLength: _sqlServerConfigs.length,
                  sybaseConfigsLength: _sybaseConfigs.length,
                  postgresConfigsLength: _postgresConfigs.length,
                  firebirdConfigsLength: _firebirdConfigs.length,
                  onSqlServerConfigsSynced: (List<SqlServerConfig> configs) {
                    setState(() {
                      _sqlServerConfigs = configs;
                    });
                  },
                  onSybaseConfigsSynced: (List<SybaseConfig> configs) {
                    setState(() {
                      _sybaseConfigs = configs;
                    });
                  },
                  onPostgresConfigsSynced: (List<PostgresConfig> configs) {
                    setState(() {
                      _postgresConfigs = configs;
                    });
                  },
                  onFirebirdConfigsSynced: (List<FirebirdConfig> configs) {
                    setState(() {
                      _firebirdConfigs = configs;
                    });
                  },
                  onSelectedConfigIdChanged: (String? id) {
                    setState(() {
                      _selectedDatabaseConfigId = id;
                    });
                  },
                ),
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
                ? ScheduleDialogSybaseLogModeSelector(
                    logBackupMode: _sybaseLogBackupMode,
                    truncateLog: _truncateLog,
                    onChanged: (SybaseLogBackupMode value) {
                      setState(() {
                        _sybaseLogBackupMode = value;
                        _truncateLog = value == SybaseLogBackupMode.truncate;
                      });
                    },
                  )
                : null,
            scheduleFields: ScheduleDialogScheduleFields(
              scheduleType: _scheduleType,
              hour: _hour,
              minute: _minute,
              selectedDaysOfWeek: _selectedDaysOfWeek,
              selectedDaysOfMonth: _selectedDaysOfMonth,
              intervalMinutesController: _intervalMinutesController,
              onHourChanged: (int value) {
                setState(() {
                  _hour = value;
                });
              },
              onMinuteChanged: (int value) {
                setState(() {
                  _minute = value;
                });
              },
              onDayOfWeekToggled: (int dayNumber, bool selected) {
                setState(() {
                  if (selected) {
                    _selectedDaysOfWeek.add(dayNumber);
                  } else if (_selectedDaysOfWeek.length > 1) {
                    _selectedDaysOfWeek.remove(dayNumber);
                  }
                  _selectedDaysOfWeek.sort();
                });
              },
              onDayOfMonthToggled: (int day, bool selected) {
                setState(() {
                  if (selected) {
                    _selectedDaysOfMonth.add(day);
                  } else if (_selectedDaysOfMonth.length > 1) {
                    _selectedDaysOfMonth.remove(day);
                  }
                  _selectedDaysOfMonth.sort();
                });
              },
              onIntervalMinutesChanged: (int minutes) {
                setState(() {
                  _intervalMinutes = minutes;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return ScheduleDialogSettingsTab(
      destinationSelector: ScheduleDialogDestinationSelector(
        destinations: _destinations,
        selectedDestinationIds: _selectedDestinationIds,
        onDestinationToggled: (String destinationId, bool selected) {
          setState(() {
            if (selected) {
              _selectedDestinationIds.add(destinationId);
            } else {
              _selectedDestinationIds.remove(destinationId);
            }
          });
        },
      ),
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

  Future<void> _selectBackupFolder() async {
    final result = await FilePicker.getDirectoryPath(
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
  Future<bool> _checkWinRarAvailable() =>
      WinrarInstallProbe.isInstalledInSystem();

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
    // Importante: NAO chamar `normalizeBackupTypeForDatabase` aqui.
    // Esse helper so existe para sanitizar troca de SGBD no dropdown
    // (e em initState para schedules importados). No save, o tipo ja
    // foi escolhido pelo utilizador e qualquer coercao silenciosa
    // (ex.: Diferencial Firebird -> Full) destroi cadeias incrementais
    // sem aviso.
    final effectiveBackupType = _backupType;

    int? firebirdNbackupPhysicalLevel;
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
                  '(automático).',
            ),
          );
          return;
        }
        firebirdNbackupPhysicalLevel = v;
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
    final hasChecksum = licenseProvider.isFeatureUnlocked(
      LicenseFeatures.checksum,
    );

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

    if (_databaseType == DatabaseType.sqlServer) {
      final validation = sqlServerBackupOptions.validate();
      if (!validation.isValid) {
        unawaited(
          FluentInfoBarFeedback.showWarning(
            context,
            message: 'Opções SQL Server inválidas: ${validation.errorMessage}',
          ),
        );
        return;
      }
    }

    final draft = ScheduleDialogDraft(
      id: widget.schedule?.id,
      name: _nameController.text.trim(),
      databaseConfigId: _selectedDatabaseConfigId!,
      databaseType: _databaseType,
      scheduleTypeString: scheduleTypeString,
      scheduleConfigJson: scheduleConfigJson,
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
      sybaseBackupOptions: _databaseType == DatabaseType.sybase
          ? SybaseBackupOptions(
              checkpointLog: _sybaseCheckpointLog,
              serverSide: _sybaseServerSide,
              autoTuneWriters: _sybaseAutoTuneWriters,
              blockSize: _sybaseBlockSize,
              logBackupMode: _sybaseLogBackupMode,
            )
          : null,
      firebirdNbackupPhysicalLevel: firebirdNbackupPhysicalLevel,
      isConvertedDifferential: widget.schedule?.isConvertedDifferential,
    );

    if (mounted) {
      Navigator.of(context).pop(draft.toSchedule());
    }
  }
}
