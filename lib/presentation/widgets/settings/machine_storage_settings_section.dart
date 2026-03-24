import 'dart:io';

import 'package:backup_database/application/services/legacy_sqlite_folder_import_service.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/elevated_legacy_profile_scan_outcome.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/machine_storage_migration.dart';
import 'package:backup_database/core/utils/windows_legacy_profile_elevated_scan.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class MachineStorageSettingsSection extends StatefulWidget {
  const MachineStorageSettingsSection({super.key});

  @override
  State<MachineStorageSettingsSection> createState() =>
      _MachineStorageSettingsSectionState();
}

class _MachineStorageSettingsSectionState
    extends State<MachineStorageSettingsSection> {
  bool _isImportingSqlite = false;
  bool _isScanningLegacyProfiles = false;
  List<String> _detectedOtherProfileLegacyPaths = const <String>[];
  String? _selectedOtherProfileLegacyPath;
  DateTime? _lastLegacyProfileScanAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadLegacyOtherProfilePaths();
      }
    });
  }

  String? _scanRecencyCaption(BuildContext context) {
    final t = _lastLegacyProfileScanAt;
    if (t == null) {
      return null;
    }
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 15) {
      return appLocaleString(
        context,
        'Última pesquisa: agora',
        'Last scan: just now',
      );
    }
    if (d.inMinutes < 1) {
      return appLocaleString(
        context,
        'Última pesquisa: há instantes',
        'Last scan: moments ago',
      );
    }
    if (d.inHours < 1) {
      return appLocaleString(
        context,
        'Última pesquisa: há ${d.inMinutes} min',
        'Last scan: ${d.inMinutes} min ago',
      );
    }
    if (d.inHours < 24) {
      return appLocaleString(
        context,
        'Última pesquisa: há ${d.inHours} h',
        'Last scan: ${d.inHours} h ago',
      );
    }
    return appLocaleString(
      context,
      'Última pesquisa: há ${d.inDays} dia(s)',
      'Last scan: ${d.inDays} day(s) ago',
    );
  }

  Future<void> _loadLegacyOtherProfilePaths() async {
    if (!Platform.isWindows) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _isScanningLegacyProfiles = true);
    try {
      final paths = await findLegacyBackupDatabasePathsOutsideCurrentUser();
      if (!mounted) {
        return;
      }
      setState(() {
        _detectedOtherProfileLegacyPaths = paths;
        _selectedOtherProfileLegacyPath = paths.isNotEmpty ? paths.first : null;
        _isScanningLegacyProfiles = false;
        _lastLegacyProfileScanAt = DateTime.now();
      });
    } on Object catch (e, s) {
      LoggerService.warning(
        'Falha ao procurar perfis Windows com bases legadas',
        e,
        s,
      );
      if (mounted) {
        setState(() => _isScanningLegacyProfiles = false);
      }
    }
  }

  Future<void> _elevatedRescanAndMerge() async {
    if (!Platform.isWindows || !mounted) {
      return;
    }
    setState(() => _isScanningLegacyProfiles = true);
    try {
      final outcome = await runElevatedLegacyProfileScanToMachineConfig();
      if (!mounted) {
        return;
      }
      if (outcome.userCancelledOrFailed) {
        setState(() => _isScanningLegacyProfiles = false);
        final String message;
        if (outcome.userDismissedUac) {
          message = appLocaleString(
            context,
            'O pedido de administrador foi cancelado ou recusado. '
                'Para pesquisar outros perfis, aceite o UAC ou importe por pasta.',
            'The administrator prompt was cancelled or denied. '
                'To scan other profiles, accept UAC or use folder import.',
          );
        } else if (outcome.failureKind ==
            ElevatedLegacyScanFailureKind.invalidJson) {
          message = appLocaleString(
            context,
            'O resultado da pesquisa elevada estava incompleto ou inválido. '
                'Tente novamente ou use importação por pasta.',
            'The elevated scan output was incomplete or invalid. '
                'Try again or use folder import.',
          );
        } else {
          message = appLocaleString(
            context,
            'Não foi possível concluir a pesquisa elevada. '
                'Tente importação por pasta ou execute a aplicação '
                'como administrador.',
            'Elevated scan did not complete. Try folder import or run '
                'the application as administrator.',
          );
        }
        await MessageModal.showWarning(context, message: message);
        return;
      }
      final merged = await mergeLegacyProfilePathsExcludingCurrentUser(
        elevatedPaths: outcome.paths,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _detectedOtherProfileLegacyPaths = merged;
        _selectedOtherProfileLegacyPath = merged.isNotEmpty
            ? merged.first
            : null;
        _isScanningLegacyProfiles = false;
        _lastLegacyProfileScanAt = DateTime.now();
      });
    } on Object catch (e, s) {
      LoggerService.warning('Pesquisa elevada de perfis falhou', e, s);
      if (mounted) {
        setState(() => _isScanningLegacyProfiles = false);
        await MessageModal.showError(context, message: '$e');
      }
    }
  }

  Future<bool> _showSqliteImportConfirmDialog({String? sourcePathLine}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return ContentDialog(
          title: Text(
            appLocaleString(
              dialogContext,
              'Importar bases de dados',
              'Import databases',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  appLocaleString(
                    dialogContext,
                    'Serão copiados ficheiros .db válidos (cabeçalho SQLite e '
                        'verificação rápida), incluindo -wal/-shm. Bases já '
                        'existentes com conteúdo não serão substituídas. '
                        'Feche outras instâncias que usem a base na origem. '
                        'Reinicie a aplicação após importar.',
                    'Valid .db files (SQLite header and quick check), '
                        'including -wal/-shm, will be copied. Non-empty '
                        'existing databases will not be replaced. Close other '
                        'apps using the source database. Restart the app after '
                        'importing.',
                  ),
                ),
                if (sourcePathLine != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    appLocaleString(
                      dialogContext,
                      'Pasta de origem:',
                      'Source folder:',
                    ),
                    style: FluentTheme.of(dialogContext).typography.caption,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(sourcePathLine),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            Button(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                appLocaleString(dialogContext, 'Cancelar', 'Cancel'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                appLocaleString(dialogContext, 'Continuar', 'Continue'),
              ),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _showSqliteImportOutcome(
    LegacySqliteFolderImportResult result,
  ) async {
    final buf = StringBuffer();
    if (result.bundlesCopied > 0) {
      buf.writeln(
        appLocaleString(
          context,
          'Pacotes copiados: ${result.bundlesCopied}.',
          'Bundles copied: ${result.bundlesCopied}.',
        ),
      );
    } else {
      buf.writeln(
        appLocaleString(
          context,
          'Nenhum pacote novo foi copiado.',
          'No new bundles were copied.',
        ),
      );
    }
    if (result.bundlesSkippedDestinationNotEmpty.isNotEmpty) {
      buf.writeln(
        appLocaleString(
          context,
          'Ignorados (destino já tem dados): '
              '${result.bundlesSkippedDestinationNotEmpty.join(", ")}.',
          'Skipped (destination already has data): '
              '${result.bundlesSkippedDestinationNotEmpty.join(", ")}.',
        ),
      );
    }
    if (result.bundlesSkippedSourceMissingOrEmpty.isNotEmpty) {
      buf.writeln(
        appLocaleString(
          context,
          'Sem ficheiro .db na origem: '
              '${result.bundlesSkippedSourceMissingOrEmpty.join(", ")}.',
          'No .db file in source: '
              '${result.bundlesSkippedSourceMissingOrEmpty.join(", ")}.',
        ),
      );
    }
    if (result.bundlesSkippedInvalidSqliteHeader.isNotEmpty) {
      buf.writeln(
        appLocaleString(
          context,
          'Cabeçalho SQLite inválido: '
              '${result.bundlesSkippedInvalidSqliteHeader.join(", ")}.',
          'Invalid SQLite header: '
              '${result.bundlesSkippedInvalidSqliteHeader.join(", ")}.',
        ),
      );
    }
    if (result.bundlesSkippedQuickCheckFailed.isNotEmpty) {
      buf.writeln(
        appLocaleString(
          context,
          'Falha na verificação rápida (ficheiro danificado?): '
              '${result.bundlesSkippedQuickCheckFailed.join(", ")}.',
          'Quick check failed (corrupt file?): '
              '${result.bundlesSkippedQuickCheckFailed.join(", ")}.',
        ),
      );
    }
    if (result.bundlesCopyFailed.isNotEmpty) {
      buf.writeln(
        appLocaleString(
          context,
          'Erros na cópia: ${result.bundlesCopyFailed.join("; ")}.',
          'Copy errors: ${result.bundlesCopyFailed.join("; ")}.',
        ),
      );
    }
    await MessageModal.showSuccess(
      context,
      message: buf.toString().trim(),
    );
  }

  Future<void> _executeSqliteImport(Directory sourceDir) async {
    setState(() => _isImportingSqlite = true);
    try {
      final result = await getIt<LegacySqliteFolderImportService>()
          .importFromFolder(
            sourceDir,
          );
      if (!mounted) {
        return;
      }
      await _showSqliteImportOutcome(result);
    } on Object catch (e) {
      if (mounted) {
        final msg = e is FileSystemException
            ? appLocaleString(
                context,
                'Não foi possível copiar (ficheiro em uso ou sem permissão): '
                    '$e',
                'Could not copy (file in use or permission denied): $e',
              )
            : '$e';
        await MessageModal.showError(context, message: msg);
      }
    } finally {
      if (mounted) {
        setState(() => _isImportingSqlite = false);
      }
    }
  }

  Future<void> _openMachineStorageFolder() async {
    try {
      final root = await resolveMachineRootDirectory();
      final uri = Uri.directory(root.path, windows: Platform.isWindows);
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) {
        return;
      }
      if (!ok) {
        await MessageModal.showWarning(
          context,
          message: appLocaleString(
            context,
            'Não foi possível abrir a pasta.',
            'Could not open the folder.',
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        await MessageModal.showError(context, message: '$e');
      }
    }
  }

  Future<void> _importSqliteDatabasesFromFolder() async {
    final confirmed = await _showSqliteImportConfirmDialog();
    if (!confirmed || !mounted) {
      return;
    }

    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: appLocaleString(
        context,
        'Pasta com ficheiros SQLite (.db)',
        'Folder with SQLite database files',
      ),
    );
    if (picked == null || !mounted) {
      return;
    }

    await _executeSqliteImport(Directory(picked));
  }

  Future<void> _importSqliteFromSelectedWindowsProfile() async {
    final path = _selectedOtherProfileLegacyPath;
    if (path == null || path.isEmpty) {
      if (mounted) {
        await MessageModal.showWarning(
          context,
          message: appLocaleString(
            context,
            'Selecione um perfil na lista.',
            'Select a profile from the list.',
          ),
        );
      }
      return;
    }

    final confirmed = await _showSqliteImportConfirmDialog(
      sourcePathLine: path,
    );
    if (!confirmed || !mounted) {
      return;
    }

    await _executeSqliteImport(Directory(path));
  }

  @override
  Widget build(BuildContext context) {
    final scanCaption = _scanRecencyCaption(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          appLocaleString(
            context,
            'Armazenamento na máquina',
            'Machine storage',
          ),
          style: FluentTheme.of(context).typography.subtitle,
        ),
        const SizedBox(height: 8),
        Text(
          appLocaleString(
            context,
            'Dados partilhados por todos os utilizadores neste PC '
                '(ProgramData no Windows). Use importação se copiou '
                'bases de outro perfil ou backup manual.',
            'Data shared by all users on this PC (ProgramData on '
                'Windows). Use import if you copied databases from '
                'another profile or a manual backup.',
          ),
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        Semantics(
          button: true,
          label: appLocaleString(
            context,
            'Abrir pasta de armazenamento na máquina',
            'Open machine storage folder',
          ),
          child: FilledButton(
            onPressed: _openMachineStorageFolder,
            child: Text(
              appLocaleString(
                context,
                'Abrir pasta de armazenamento',
                'Open storage folder',
              ),
            ),
          ),
        ),
        if (Platform.isWindows) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            appLocaleString(
              context,
              'Outros perfis Windows (SQLite legado)',
              'Other Windows profiles (legacy SQLite)',
            ),
            style: FluentTheme.of(context).typography.bodyStrong,
          ),
          const SizedBox(height: 8),
          Text(
            appLocaleString(
              context,
              r'Perfis em C:\Users\… com bases em AppData\Roaming\Backup Database. '
                  'Sem permissão de leitura, o perfil não aparece — use '
                  '"Pesquisar como administrador" ou importação por pasta.',
              r'Profiles under C:\Users\… with databases in '
                  r'AppData\Roaming\Backup Database. '
                  'Without read permission use "Scan as administrator" or '
                  'folder import.',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          if (scanCaption != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              scanCaption,
              style: FluentTheme.of(context).typography.caption,
            ),
          ],
          const SizedBox(height: 12),
          if (_isScanningLegacyProfiles)
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    appLocaleString(
                      context,
                      'A procurar outros perfis…',
                      'Scanning other profiles…',
                    ),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ),
                const IconButton(
                  icon: Icon(FluentIcons.refresh),
                  onPressed: null,
                ),
              ],
            )
          else ...<Widget>[
            if (_detectedOtherProfileLegacyPaths.isEmpty)
              Text(
                appLocaleString(
                  context,
                  'Nenhum outro perfil com bases detetadas.',
                  'No other profile with databases detected.',
                ),
                style: FluentTheme.of(context).typography.caption,
              )
            else ...<Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      label: appLocaleString(
                        context,
                        'Selecionar perfil Windows com bases de dados legadas',
                        'Select Windows profile with legacy databases',
                      ),
                      child: ComboBox<String>(
                        value: _selectedOtherProfileLegacyPath,
                        items: _detectedOtherProfileLegacyPaths.map((
                          String path,
                        ) {
                          final label = legacyWindowsProfileFolderLabel(path);
                          return ComboBoxItem<String>(
                            value: path,
                            child: Text(label),
                          );
                        }).toList(),
                        onChanged: _isImportingSqlite
                            ? null
                            : (String? v) {
                                setState(
                                  () => _selectedOtherProfileLegacyPath = v,
                                );
                              },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(FluentIcons.refresh),
                    onPressed: _isImportingSqlite
                        ? null
                        : _loadLegacyOtherProfilePaths,
                  ),
                ],
              ),
              if (_selectedOtherProfileLegacyPath != null) ...<Widget>[
                const SizedBox(height: 8),
                SelectableText(
                  _selectedOtherProfileLegacyPath!,
                  style: FluentTheme.of(context).typography.caption,
                ),
              ],
              const SizedBox(height: 8),
              Semantics(
                button: true,
                label: appLocaleString(
                  context,
                  'Importar bases SQLite da pasta do perfil selecionado',
                  'Import SQLite databases from selected profile folder',
                ),
                child: Button(
                  onPressed: _isImportingSqlite
                      ? null
                      : _importSqliteFromSelectedWindowsProfile,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (_isImportingSqlite) ...<Widget>[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: ProgressRing(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        appLocaleString(
                          context,
                          'Importar da pasta deste perfil',
                          'Import from this profile folder',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Button(
                onPressed: _isImportingSqlite ? null : _elevatedRescanAndMerge,
                child: Text(
                  appLocaleString(
                    context,
                    'Pesquisar como administrador…',
                    'Scan as administrator…',
                  ),
                ),
              ),
            ],
            if (!_isScanningLegacyProfiles &&
                _detectedOtherProfileLegacyPaths.isEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Button(
                onPressed: _isImportingSqlite ? null : _elevatedRescanAndMerge,
                child: Text(
                  appLocaleString(
                    context,
                    'Pesquisar como administrador…',
                    'Scan as administrator…',
                  ),
                ),
              ),
            ],
          ],
        ],
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: appLocaleString(
            context,
            'Importar bases SQLite a partir de uma pasta no disco',
            'Import SQLite databases from a folder on disk',
          ),
          child: Button(
            onPressed: _isImportingSqlite
                ? null
                : _importSqliteDatabasesFromFolder,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_isImportingSqlite) ...<Widget>[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: ProgressRing(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  appLocaleString(
                    context,
                    'Importar bases SQLite de uma pasta…',
                    'Import SQLite databases from folder…',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),
      ],
    );
  }
}
