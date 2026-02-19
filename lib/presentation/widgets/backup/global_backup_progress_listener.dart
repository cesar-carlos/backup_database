import 'package:backup_database/application/providers/backup_progress_provider.dart';
import 'package:backup_database/core/routes/app_router.dart';
import 'package:backup_database/presentation/widgets/backup/backup_progress_dialog.dart';
import 'package:flutter/material.dart';

class GlobalBackupProgressListener extends StatefulWidget {
  const GlobalBackupProgressListener({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<GlobalBackupProgressListener> createState() =>
      _GlobalBackupProgressListenerState();
}

class _GlobalBackupProgressListenerState
    extends State<GlobalBackupProgressListener> {
  bool _isDialogVisible = false;
  late BackupProgressProvider _provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListener();
    });
  }

  void _setupListener() {
    _provider = BackupProgressProvider.of(context);
    _provider.addListener(_onProgressChanged);
    _checkAndShowDialog();
  }

  void _onProgressChanged() {
    _checkAndShowDialog();
  }

  void _checkAndShowDialog() {
    final shouldBeVisible = _provider.isRunning;

    if (shouldBeVisible && !_isDialogVisible) {
      _isDialogVisible = true;
      _showDialog();
    } else if (!shouldBeVisible && _isDialogVisible) {
      _isDialogVisible = false;
    }
  }

  void _showDialog() {
    if (!mounted) return;

    final dialogContext = appNavigatorKey.currentContext ?? context;

    BackupProgressDialog.show(dialogContext).then((_) {
      if (mounted) {
        _provider.reset();
        setState(() {
          _isDialogVisible = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _provider.removeListener(_onProgressChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
