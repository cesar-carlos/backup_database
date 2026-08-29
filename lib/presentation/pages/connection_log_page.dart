import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/server/server.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ConnectionLogPage extends StatelessWidget {
  const ConnectionLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppPageScaffold(
      title: 'Log de Conexões',
      body: ConnectionLogsList(),
    );
  }
}
