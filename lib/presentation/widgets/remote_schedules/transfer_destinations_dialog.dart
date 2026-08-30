import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class TransferDestinationsDialog extends StatefulWidget {
  const TransferDestinationsDialog({
    required this.scheduleName,
    required this.destinations,
    required this.initialSelectedIds,
    super.key,
  });

  final String scheduleName;
  final List<BackupDestination> destinations;
  final Set<String> initialSelectedIds;

  @override
  State<TransferDestinationsDialog> createState() =>
      _TransferDestinationsDialogState();
}

class _TransferDestinationsDialogState
    extends State<TransferDestinationsDialog> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initialSelectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialogShell(
      title: const Text('Destinos após transferir'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ao transferir um backup do agendamento "${widget.scheduleName}", '
              'enviar também para:',
              style: FluentTheme.of(context).typography.body,
            ),
            const SizedBox(height: AppSpacing.md),
            ...widget.destinations.map(
              (d) => Checkbox(
                checked: _selectedIds.contains(d.id),
                onChanged: (value) {
                  setState(() {
                    if (value ?? false) {
                      _selectedIds.add(d.id);
                    } else {
                      _selectedIds.remove(d.id);
                    }
                  });
                },
                content: Row(
                  children: [
                    Text(d.name),
                    const SizedBox(width: 8),
                    DestinationTypeBadge(type: d.type),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        CancelButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
        SaveButton(
          onPressed: () => Navigator.of(context).pop(_selectedIds),
        ),
      ],
    );
  }
}
