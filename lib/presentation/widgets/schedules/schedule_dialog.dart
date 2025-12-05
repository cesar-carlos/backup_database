import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../application/providers/providers.dart';
import '../../../domain/entities/schedule.dart';
import '../../../domain/entities/sql_server_config.dart';
import '../../../domain/entities/sybase_config.dart';
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

  final _nameController = TextEditingController();
  final _intervalMinutesController = TextEditingController();

  DatabaseType _databaseType = DatabaseType.sqlServer;
  String? _selectedDatabaseConfigId;
  ScheduleType _scheduleType = ScheduleType.daily;
  List<String> _selectedDestinationIds = [];
  bool _compressBackup = true;
  bool _isEnabled = true;

  // Schedule config
  int _hour = 0;
  int _minute = 0;
  List<int> _selectedDaysOfWeek = [1]; // Segunda
  List<int> _selectedDaysOfMonth = [1];
  int _intervalMinutes = 60;

  List<SqlServerConfig> _sqlServerConfigs = [];
  List<SybaseConfig> _sybaseConfigs = [];
  List<BackupDestination> _destinations = [];
  bool _isLoading = true;

  bool get isEditing => widget.schedule != null;

  @override
  void initState() {
    super.initState();
    _intervalMinutesController.text = _intervalMinutes.toString();

    if (widget.schedule != null) {
      _nameController.text = widget.schedule!.name;
      _databaseType = widget.schedule!.databaseType;
      _selectedDatabaseConfigId = widget.schedule!.databaseConfigId;
      _scheduleType = widget.schedule!.scheduleType;
      _selectedDestinationIds = List.from(widget.schedule!.destinationIds);
      _compressBackup = widget.schedule!.compressBackup;
      _isEnabled = widget.schedule!.enabled;

      _parseScheduleConfig(widget.schedule!.scheduleConfig);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
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
    final destinationProvider = context.read<DestinationProvider>();

    await Future.wait([
      sqlServerProvider.loadConfigs(),
      sybaseProvider.loadConfigs(),
      destinationProvider.loadDestinations(),
    ]);

    if (mounted) {
      setState(() {
        _sqlServerConfigs = sqlServerProvider.configs;
        _sybaseConfigs = sybaseProvider.configs;
        _destinations = destinationProvider.destinations;

        if (_selectedDatabaseConfigId != null) {
          final exists = _databaseType == DatabaseType.sqlServer
              ? _sqlServerConfigs.any((c) => c.id == _selectedDatabaseConfigId)
              : _sybaseConfigs.any((c) => c.id == _selectedDatabaseConfigId);

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

  @override
  @override
  void dispose() {
    _nameController.dispose();
    _intervalMinutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(
        minWidth: 600,
        maxWidth: 600,
        maxHeight: 800,
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
        constraints: const BoxConstraints(),
        child: _isLoading
            ? const Center(child: ProgressRing())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
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
                      _buildScheduleFields(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Destinos'),
                      const SizedBox(height: 12),
                      _buildDestinationSelector(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Opções'),
                      const SizedBox(height: 12),
                      InfoLabel(
                        label: 'Compactar backup',
                        child: ToggleSwitch(
                          checked: _compressBackup,
                          onChanged: (value) {
                            setState(() {
                              _compressBackup = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Gerar arquivo ZIP do backup',
                        style: FluentTheme.of(context).typography.caption,
                      ),
                      const SizedBox(height: 16),
                      InfoLabel(
                        label: 'Habilitado',
                        child: ToggleSwitch(
                          checked: _isEnabled,
                          onChanged: (value) {
                            setState(() {
                              _isEnabled = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Agendamento ativo',
                        style: FluentTheme.of(context).typography.caption,
                      ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        const CancelButton(),
        SaveButton(onPressed: _save, isEditing: isEditing),
      ],
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

          return ComboBox<String>(
            key: ValueKey(
              'database_config_sqlserver_${_databaseType}_${sqlServerItems.length}_${_selectedDatabaseConfigId ?? 'null'}',
            ),
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

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedDestinationIds.isEmpty) {
      MessageModal.showWarning(
        context,
        message: 'Selecione pelo menos um destino',
      );
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
      compressBackup: _compressBackup,
      enabled: _isEnabled,
      lastRunAt: widget.schedule?.lastRunAt,
      nextRunAt: widget.schedule?.nextRunAt,
      createdAt: widget.schedule?.createdAt,
    );

    Navigator.of(context).pop(schedule);
  }
}
