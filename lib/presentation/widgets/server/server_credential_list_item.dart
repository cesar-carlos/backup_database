import 'package:backup_database/domain/entities/server_credential.dart';
import 'package:backup_database/presentation/widgets/common/config_list_item.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ServerCredentialListItem extends StatelessWidget {
  const ServerCredentialListItem({
    required this.credential,
    super.key,
    this.onEdit,
    this.onDelete,
    this.onToggleActive,
  });
  final ServerCredential credential;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleActive;

  String _t(BuildContext context, String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  @override
  Widget build(BuildContext context) {
    return ConfigListItem(
      name: credential.name,
      icon: FluentIcons.lock,
      enabled: credential.isActive,
      onToggleEnabled: onToggleActive,
      onEdit: onEdit,
      onDelete: onDelete,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            '${_t(context, 'ID do servidor', 'Server ID')}: ${credential.serverId}',
            style: FluentTheme.of(context).typography.body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (credential.description != null &&
              credential.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              credential.description!,
              style: FluentTheme.of(context).typography.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
