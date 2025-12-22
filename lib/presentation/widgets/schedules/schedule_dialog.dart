import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/core.dart';
import '../../../application/providers/providers.dart';
import '../../../domain/entities/backup_type.dart';
import '../../../domain/entities/schedule.dart';
import '../../../domain/entities/sql_server_config.dart';
import '../../../domain/entities/sybase_config.dart';
import '../../../domain/entities/postgres_config.dart';
import '../../../domain/entities/backup_destination.dart';
import '../common/common.dart';

class ScheduleDialog extends StatefulWidget {
  final Schedule? schedule;

  const ScheduleDialog({super.key, this.schedule});

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

  final _nameController = TextEditingController();
  final _intervalMinutesController = TextEditingController();
  final _backupFolderController = TextEditingController();
  final _postBackupScriptController = TextEditingController();

  DatabaseType _databaseType = DatabaseType.sqlServer;
  String? _selectedDatabaseConfigId;
  ScheduleType _scheduleType = ScheduleType.daily;
  BackupType _backupType = BackupType.full;
  bool _truncateLog = true;
  List<String> _selectedDestinationIds = [];
  bool _compressBackup = true;
  bool _isEnabled = true;
  bool _enableChecksum = false;
  bool _verifyAfterBackup = false;

  // Schedule config
  int _hour = 0;
  int _minute = 0;
  List<int> _selectedDaysOfWeek = [1]; // Segunda
  List<int> _selectedDaysOfMonth = [1];
  int _intervalMinutes = 60;

  List<SqlServerConfig> _sqlServerConfigs = [];
  List<SybaseConfig> _sybaseConfigs = [];
  List<PostgresConfig> _postgresConfigs = [];
  List<BackupDestination> _destinations = [];
  bool _isLoading = true;

  bool get isEditing => widget.schedule != null;

  @override
  void initState() {
    super.initState();
    _intervalMinutesController.text = _intervalMinutes.toString();
    _backupFolderController.text = _getDefaultBackupFolder();

    if (widget.schedule != null) {
      _nameController.text = widget.schedule!.name;
      _databaseType = widget.schedule!.databaseType;
      _selectedDatabaseConfigId = widget.schedule!.databaseConfigId;
      _scheduleType = widget.schedule!.scheduleType;
      _backupType = widget.schedule!.backupType;
      _truncateLog = widget.schedule!.truncateLog;
      if (_databaseType == DatabaseType.sybase &&
          _backupType == BackupType.differential) {
        _backupType = BackupType.full;
        _truncateLog = true;
      }
      _selectedDestinationIds = List.from(widget.schedule!.destinationIds);
      _compressBackup = widget.schedule!.compressBackup;
      _isEnabled = widget.schedule!.enabled;
      _enableChecksum = widget.schedule!.enableChecksum;
      _verifyAfterBackup = widget.schedule!.verifyAfterBackup;
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
        'C:\\Temp';
    return '$systemTemp\\BackupDatabase';
  }

  void _parseScheduleConfig(String configJson) {
    try {
      final config = jsonDecode(configJson) as Map<String, dynamic>;

      switch (_scheduleType) {
        case ScheduleType.daily:
          _hour = config['hour'] ?? 0;
          _minute = config['minute'] ?? 0;
          break;
        case ScheduleType.weekly:
          _selectedDaysOfWeek =
              (config['daysOfWeek'] as List?)?.cast<int>() ?? [1];
          _hour = config['hour'] ?? 0;
          _minute = config['minute'] ?? 0;
          break;
        case ScheduleType.monthly:
          _selectedDaysOfMonth =
              (config['daysOfMonth'] as List?)?.cast<int>() ?? [1];
          _hour = config['hour'] ?? 0;
          _minute = config['minute'] ?? 0;
          break;
        case ScheduleType.interval:
          _intervalMinutes = config['intervalMinutes'] ?? 60;
          _intervalMinutesController.text = _intervalMinutes.toString();
          break;
      }
    } catch (e) {
      // Use defaults
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

  List<BackupType> _getAvailableBackupTypes() {
    if (_databaseType == DatabaseType.sybase) {
      return const [BackupType.full, BackupType.log];
    }
    if (_databaseType == DatabaseType.postgresql) {
      return const [
        BackupType.full,
        BackupType.fullSingle,
        BackupType.differential,
        BackupType.log,
      ];
    }
    return BackupType.values;
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
        minWidth: 700,
        maxWidth: 800,
        maxHeight: 750,
      ),
      title: Row(
        children: [
          Icon(FluentIcons.calendar, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(
            isEditing ? 'Editar Agendamento' : 'Novo Agendamento',
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
                      text: const Text('Geral'),
                      icon: const Icon(FluentIcons.settings),
                      body: _buildGeneralTab(),
                    ),
                    Tab(
                      text: const Text('Configurações'),
                      icon: const Icon(FluentIcons.folder),
                      body: _buildSettingsTab(),
                    ),
                    Tab(
                      text: const Text('Script SQL'),
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
              if (value == null || value.trim().isEmpty) {
                return 'Nome é obrigatório';
              }
              return null;
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
          AppDropdown<BackupType>(
            label: 'Tipo de Backup',
            value: _backupType,
            placeholder: const Text('Tipo de Backup'),
            items: _getAvailableBackupTypes().map((type) {
              return ComboBoxItem<BackupType>(
                value: type,
                child: Text(type.displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _backupType = value;
                  _onBackupTypeChanged();
                });
              }
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
          AppDropdown<ScheduleType>(
            label: 'Frequência',
            value: _scheduleType,
            placeholder: const Text('Frequência'),
            items: ScheduleType.values.map((type) {
              return ComboBoxItem<ScheduleType>(
                value: type,
                child: Text(_getScheduleTypeName(type)),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _scheduleType = value;
                });
              }
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
          _buildSectionTitle('Destinos'),
          const SizedBox(height: 12),
          _buildDestinationSelector(),
          const SizedBox(height: 24),
          _buildSectionTitle('Pasta de Backup'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _backupFolderController,
                  label: 'Pasta para Armazenar Backup',
                  hint: 'C:\\Backups',
                  prefixIcon: const Icon(FluentIcons.folder),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Pasta de backup é obrigatória';
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
            'Pasta onde o arquivo de backup será gerado antes de enviar aos destinos',
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Opções'),
          const SizedBox(height: 12),
          InfoLabel(
            label: 'Compactar backup (gera ZIP)',
            child: ToggleSwitch(
              checked: _compressBackup,
              onChanged: (value) {
                setState(() {
                  _compressBackup = value;
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Agendamento habilitado',
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
          _buildIntegrityOptions(),
        ],
      ),
    );
  }

  Widget _buildIntegrityOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('Verificação de Integridade'),
        const SizedBox(height: 12),
        if (_databaseType == DatabaseType.sqlServer) ...[
          _buildCheckboxWithInfo(
            label: 'Enable CheckSum',
            value: _enableChecksum,
            onChanged: (value) {
              setState(() {
                _enableChecksum = value;
              });
            },
            infoText:
                'Habilita o cálculo de checksums durante o backup. '
                'Detecta corrupção de dados durante o processo de backup.',
          ),
          const SizedBox(height: 16),
        ],
        _buildCheckboxWithInfo(
          label: 'Verify After Backup',
          value: _verifyAfterBackup,
          onChanged: (value) {
            setState(() {
              _verifyAfterBackup = value;
            });
          },
          infoText: _databaseType == DatabaseType.sqlServer
              ? 'Verifica a integridade do backup após criação usando RESTORE VERIFYONLY. '
                    'Garante que o backup pode ser restaurado sem restaurar os dados.'
              : _databaseType == DatabaseType.postgresql
              ? 'Verifica a integridade do backup após criação usando pg_verifybackup. '
                    'Garante que o backup está íntegro e pode ser restaurado.'
              : 'Verifica a integridade do backup após criação usando dbverify. '
                    'Garante que o backup está íntegro e pode ser restaurado.',
        ),
      ],
    );
  }

  Widget _buildCheckboxWithInfo({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String infoText,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InfoLabel(
            label: label,
            child: Checkbox(
              checked: value,
              onChanged: (checked) => onChanged(checked ?? false),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('Script SQL Pós-Backup (Opcional)'),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Script SQL',
            child: TextBox(
              controller: _postBackupScriptController,
              placeholder:
                  'Ex: UPDATE tabela SET status = \'backup_completo\' WHERE id = 1;',
              maxLines: 15,
              minLines: 10,
            ),
          ),
          const SizedBox(height: 16),
          InfoBar(
            title: const Text('Informação'),
            content: const Text(
              'O script será executado na mesma conexão do backup, '
              'após o backup ser concluído com sucesso. '
              'Erros no script não impedem o backup de ser considerado bem-sucedido.',
            ),
            severity: InfoBarSeverity.info,
          ),
        ],
      ),
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
                      value: null,
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
                      value: null,
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
                    value: null,
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
                if (value == true) {
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
                if (value == true) {
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
            Icon(FluentIcons.warning, color: AppColors.error),
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

    return Column(
      children: _destinations.map((destination) {
        final isSelected = _selectedDestinationIds.contains(destination.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(_getDestinationIcon(destination.type)),
            title: Text(destination.name),
            subtitle: Text(_getDestinationTypeName(destination.type)),
            trailing: Checkbox(
              checked: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedDestinationIds.add(destination.id);
                  } else {
                    _selectedDestinationIds.remove(destination.id);
                  }
                });
              },
            ),
          ),
        );
      }).toList(),
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
          return 'Backup de arquivos WAL (Write-Ahead Log) usando pg_basebackup com streaming. Requer streaming habilitado no PostgreSQL.';
        case BackupType.differential:
          return 'Backup incremental usando pg_basebackup. Requer backup FULL anterior com manifest. (PostgreSQL 17+)';
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

      if (shouldCreate == true) {
        try {
          await directory.create(recursive: true);
        } catch (e) {
          if (mounted) {
            MessageModal.showError(context, message: 'Erro ao criar pasta: $e');
          }
          return false;
        }
      } else {
        return false;
      }
    }

    // Validar permissão de escrita
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
      // Tentar criar um arquivo temporário para testar permissão
      final testFileName =
          '.backup_permission_test_${DateTime.now().millisecondsSinceEpoch}';
      final testFile = File(
        '${directory.path}${Platform.pathSeparator}$testFileName',
      );

      // Tentar escrever no arquivo
      await testFile.writeAsString('test');

      // Se conseguiu escrever, deletar o arquivo
      if (await testFile.exists()) {
        await testFile.delete();
        return true;
      }

      return false;
    } catch (e) {
      LoggerService.warning(
        'Erro ao verificar permissão de escrita na pasta ${directory.path}: $e',
      );
      return false;
    }
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) {
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

    final isValidFolder = await _validateBackupFolder();
    if (!isValidFolder) {
      return;
    }

    String scheduleConfigJson;
    switch (_scheduleType) {
      case ScheduleType.daily:
        scheduleConfigJson = jsonEncode({'hour': _hour, 'minute': _minute});
        break;
      case ScheduleType.weekly:
        scheduleConfigJson = jsonEncode({
          'daysOfWeek': _selectedDaysOfWeek,
          'hour': _hour,
          'minute': _minute,
        });
        break;
      case ScheduleType.monthly:
        scheduleConfigJson = jsonEncode({
          'daysOfMonth': _selectedDaysOfMonth,
          'hour': _hour,
          'minute': _minute,
        });
        break;
      case ScheduleType.interval:
        scheduleConfigJson = jsonEncode({'intervalMinutes': _intervalMinutes});
        break;
    }

    final schedule = Schedule(
      id: widget.schedule?.id,
      name: _nameController.text.trim(),
      databaseConfigId: _selectedDatabaseConfigId!,
      databaseType: _databaseType,
      scheduleType: _scheduleType,
      scheduleConfig: scheduleConfigJson,
      destinationIds: _selectedDestinationIds,
      backupFolder: _backupFolderController.text.trim(),
      backupType: _backupType,
      compressBackup: _compressBackup,
      enabled: _isEnabled,
      enableChecksum: _databaseType == DatabaseType.sqlServer
          ? _enableChecksum
          : false,
      verifyAfterBackup: _verifyAfterBackup,
      postBackupScript: _postBackupScriptController.text.trim().isEmpty
          ? null
          : _postBackupScriptController.text.trim(),
      lastRunAt: widget.schedule?.lastRunAt,
      nextRunAt: widget.schedule?.nextRunAt,
      createdAt: widget.schedule?.createdAt,
      truncateLog: _truncateLog,
    );

    Navigator.of(context).pop(schedule);
  }
}
