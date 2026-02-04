import 'package:backup_database/presentation/widgets/server/server.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ConnectionLogPage extends StatelessWidget {
  const ConnectionLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScaffoldPage(
      header: PageHeader(title: Text('Log de Conexões')),
      content: Padding(
        padding: EdgeInsets.all(24),
        child: ConnectionLogsList(),
      ),
    );
  }
}
