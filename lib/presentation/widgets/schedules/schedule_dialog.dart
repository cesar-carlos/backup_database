import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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

    // Carregar dados após o build
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

        // Verificar se o ID selecionado ainda existe após carregar
        if (_selectedDatabaseConfigId != null) {
          final exists = _databaseType == DatabaseType.sqlServer
              ? _sqlServerConfigs.any((c) => c.id == _selectedDatabaseConfigId)
              : _sybaseConfigs.any((c) => c.id == _selectedDatabaseConfigId);

          if (!exists) {
            // Se não existe mais, limpar seleção
            _selectedDatabaseConfigId = null;
          }
        }

        // Verificar se os destinos selecionados ainda existem
        _selectedDestinationIds.removeWhere((id) {
          return !_destinations.any((d) => d.id == id);
        });

        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            Flexible(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Nome
                            AppTextField(
                              controller: _nameController,
                              label: 'Nome do Agendamento',
                              hint: 'Ex: Backup Diário Produção',
                              prefixIcon: const Icon(Icons.label_outline),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Nome é obrigatório';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),

                            // Seção: Banco de Dados
                            _buildSectionTitle('Banco de Dados'),
                            const SizedBox(height: 12),

                            // Tipo de banco
                            DropdownButtonFormField<DatabaseType>(
                              key: ValueKey('database_type_$_databaseType'),
                              initialValue: _databaseType,
                              decoration: const InputDecoration(
                                labelText: 'Tipo de Banco',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.storage_outlined),
                              ),
                              items: DatabaseType.values.map((type) {
                                return DropdownMenuItem(
                                  value: type,
                                  child: Text(_getDatabaseTypeName(type)),
                                );
                              }).toList(),
                              onChanged: isEditing
                                  ? null
                                  : (value) {
                                      setState(() {
                                        // Limpar imediatamente antes de mudar o tipo
                                        _selectedDatabaseConfigId = null;
                                        _databaseType = value!;
                                      });
                                      // Forçar validação do formulário para limpar erros
                                      _formKey.currentState?.validate();
                                    },
                            ),
                            const SizedBox(height: 16),

                            // Configuração do banco
                            Builder(
                              key: ValueKey(
                                'database_config_dropdown_${_databaseType}_${_selectedDatabaseConfigId ?? 'null'}',
                              ),
                              builder: (context) =>
                                  _buildDatabaseConfigDropdown(),
                            ),
                            const SizedBox(height: 24),

                            // Seção: Agendamento
                            _buildSectionTitle('Agendamento'),
                            const SizedBox(height: 12),

                            // Tipo de agendamento
                            DropdownButtonFormField<ScheduleType>(
                              initialValue: _scheduleType,
                              decoration: const InputDecoration(
                                labelText: 'Frequência',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.schedule_outlined),
                              ),
                              items: ScheduleType.values.map((type) {
                                return DropdownMenuItem(
                                  value: type,
                                  child: Text(_getScheduleTypeName(type)),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _scheduleType = value!;
                                });
                              },
                            ),
                            const SizedBox(height: 16),

                            // Campos específicos do agendamento
                            _buildScheduleFields(),
                            const SizedBox(height: 24),

                            // Seção: Destinos
                            _buildSectionTitle('Destinos'),
                            const SizedBox(height: 12),

                            _buildDestinationSelector(),
                            const SizedBox(height: 24),

                            // Opções
                            _buildSectionTitle('Opções'),
                            const SizedBox(height: 12),

                            SwitchListTile(
                              title: const Text('Compactar backup'),
                              subtitle: const Text(
                                'Gerar arquivo ZIP do backup',
                              ),
                              value: _compressBackup,
                              onChanged: (value) {
                                setState(() {
                                  _compressBackup = value;
                                });
                              },
                            ),
                            SwitchListTile(
                              title: const Text('Habilitado'),
                              subtitle: const Text('Agendamento ativo'),
                              value: _isEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _isEnabled = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule_outlined,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Text(
            isEditing ? 'Editar Agendamento' : 'Novo Agendamento',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(isEditing ? 'Salvar' : 'Criar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildDatabaseConfigDropdown() {
    if (_databaseType == DatabaseType.sqlServer) {
      return Consumer<SqlServerConfigProvider>(
        builder: (context, provider, child) {
          // Garantir que estamos usando apenas configurações SQL Server
          final sqlServerItems = provider.configs.map((config) {
            return DropdownMenuItem(
              value: config.id,
              child: Text(
                '${config.name} (${config.server}:${config.database})',
              ),
            );
          }).toList();

          // Atualizar lista local sincronizada
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                _sqlServerConfigs.length != provider.configs.length) {
              setState(() {
                _sqlServerConfigs = provider.configs;
              });
            }
          });

          // SEMPRE validar: se o tipo é SQL Server, só aceitar IDs de SQL Server
          // Se _selectedDatabaseConfigId não existe na lista SQL Server, deve ser null
          String? validValue;
          if (_selectedDatabaseConfigId != null) {
            final exists = sqlServerItems.any(
              (item) => item.value == _selectedDatabaseConfigId,
            );
            validValue = exists ? _selectedDatabaseConfigId : null;
            // Se não existe, limpar imediatamente
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

          return DropdownButtonFormField<String>(
            key: ValueKey(
              'database_config_sqlserver_${_databaseType}_${sqlServerItems.length}_${_selectedDatabaseConfigId ?? 'null'}',
            ),
            initialValue: validValue,
            decoration: InputDecoration(
              labelText: 'Configuração do Banco',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.dns_outlined),
              hintText: sqlServerItems.isEmpty
                  ? 'Nenhuma configuração disponível'
                  : 'Selecione uma configuração',
            ),
            items: sqlServerItems.isEmpty
                ? [
                    const DropdownMenuItem<String>(
                      value: null,
                      enabled: false,
                      child: Text(
                        'Nenhuma configuração disponível',
                        style: TextStyle(fontStyle: FontStyle.italic),
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
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Selecione uma configuração de banco';
              }
              return null;
            },
          );
        },
      );
    }

    return Consumer<SybaseConfigProvider>(
      builder: (context, provider, child) {
        // Garantir que estamos usando apenas configurações Sybase
        final sybaseItems = provider.configs.map((config) {
          return DropdownMenuItem(
            value: config.id,
            child: Text('${config.name} (${config.serverName}:${config.port})'),
          );
        }).toList();

        // Atualizar lista local sincronizada
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _sybaseConfigs.length != provider.configs.length) {
            setState(() {
              _sybaseConfigs = provider.configs;
            });
          }
        });

        // SEMPRE validar: se o tipo é Sybase, só aceitar IDs de Sybase
        // Se _selectedDatabaseConfigId não existe na lista Sybase, deve ser null
        String? validValue;
        if (_selectedDatabaseConfigId != null) {
          final exists = sybaseItems.any(
            (item) => item.value == _selectedDatabaseConfigId,
          );
          validValue = exists ? _selectedDatabaseConfigId : null;
          // Se não existe, limpar imediatamente
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

        return DropdownButtonFormField<String>(
          key: ValueKey(
            'database_config_sybase_${_databaseType}_${sybaseItems.length}_${_selectedDatabaseConfigId ?? 'null'}',
          ),
          initialValue: validValue,
          decoration: InputDecoration(
            labelText: 'Configuração do Banco',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.dns_outlined),
            hintText: sybaseItems.isEmpty
                ? 'Nenhuma configuração disponível'
                : 'Selecione uma configuração',
          ),
          items: sybaseItems.isEmpty
              ? [
                  const DropdownMenuItem<String>(
                    value: null,
                    enabled: false,
                    child: Text(
                      'Nenhuma configuração disponível',
                      style: TextStyle(fontStyle: FontStyle.italic),
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
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Selecione uma configuração de banco';
            }
            return null;
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
          child: DropdownButtonFormField<int>(
            initialValue: _hour,
            decoration: const InputDecoration(
              labelText: 'Hora',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.access_time),
            ),
            items: List.generate(24, (index) {
              return DropdownMenuItem(
                value: index,
                child: Text(index.toString().padLeft(2, '0')),
              );
            }),
            onChanged: (value) {
              setState(() {
                _hour = value!;
              });
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: _minute,
            decoration: const InputDecoration(
              labelText: 'Minuto',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.timer_outlined),
            ),
            items: List.generate(60, (index) {
              return DropdownMenuItem(
                value: index,
                child: Text(index.toString().padLeft(2, '0')),
              );
            }),
            onChanged: (value) {
              setState(() {
                _minute = value!;
              });
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

        return FilterChip(
          label: Text(days[index]),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedDaysOfWeek.add(dayNumber);
              } else if (_selectedDaysOfWeek.length > 1) {
                _selectedDaysOfWeek.remove(dayNumber);
              }
              _selectedDaysOfWeek.sort();
            });
          },
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

        return FilterChip(
          label: Text(day.toString()),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedDaysOfMonth.add(day);
              } else if (_selectedDaysOfMonth.length > 1) {
                _selectedDaysOfMonth.remove(day);
              }
              _selectedDaysOfMonth.sort();
            });
          },
        );
      }),
    );
  }

  Widget _buildIntervalSelector() {
    return AppTextField(
      initialValue: _intervalMinutes.toString(),
      label: 'Intervalo (minutos)',
      hint: 'Ex: 60 para cada hora',
      prefixIcon: const Icon(Icons.timer_outlined),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) {
        final minutes = int.tryParse(value) ?? 60;
        setState(() {
          _intervalMinutes = minutes;
        });
      },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Intervalo é obrigatório';
        }
        final minutes = int.tryParse(value);
        if (minutes == null || minutes < 1) {
          return 'Informe um valor válido';
        }
        return null;
      },
    );
  }

  Widget _buildDestinationSelector() {
    if (_destinations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Nenhum destino configurado. Configure um destino primeiro.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _destinations.map((destination) {
        final isSelected = _selectedDestinationIds.contains(destination.id);
        return CheckboxListTile(
          title: Text(destination.name),
          subtitle: Text(_getDestinationTypeName(destination.type)),
          value: isSelected,
          onChanged: (value) {
            setState(() {
              if (value == true) {
                _selectedDestinationIds.add(destination.id);
              } else {
                _selectedDestinationIds.remove(destination.id);
              }
            });
          },
          secondary: Icon(_getDestinationIcon(destination.type)),
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
        return Icons.folder_outlined;
      case DestinationType.ftp:
        return Icons.cloud_upload_outlined;
      case DestinationType.googleDrive:
        return Icons.add_to_drive_outlined;
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
