import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../application/providers/backup_progress_provider.dart';

class BackupProgressDialog extends StatelessWidget {
  const BackupProgressDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const BackupProgressDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BackupProgressProvider>(
      builder: (context, provider, child) {
        final progress = provider.currentProgress;

        if (progress == null) {
          return const SizedBox.shrink();
        }

        return AlertDialog(
          title: Row(
            children: [
              if (progress.step == BackupStep.completed)
                const Icon(Icons.check_circle, color: Colors.green)
              else if (progress.step == BackupStep.error)
                const Icon(Icons.error, color: Colors.red)
              else
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 12),
              const Text('Backup em Execução'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    progress.message,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (progress.progress != null && progress.step != BackupStep.completed) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: progress.progress,
                      backgroundColor: Colors.grey[300],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(progress.progress! * 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (progress.elapsed != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Tempo decorrido: ${_formatDuration(progress.elapsed!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                  if (progress.error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              progress.error!,
                              style: TextStyle(color: Colors.red[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (progress.step == BackupStep.completed ||
                progress.step == BackupStep.error)
              ElevatedButton(
                onPressed: () {
                  provider.reset();
                  Navigator.of(context).pop();
                },
                child: const Text('Fechar'),
              ),
          ],
        );
      },
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}

