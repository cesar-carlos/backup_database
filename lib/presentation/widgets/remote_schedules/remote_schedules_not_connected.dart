import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

/// **Organism** — empty state when no server connection is active.
class RemoteSchedulesNotConnected extends StatelessWidget {
  const RemoteSchedulesNotConnected({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPageState.empty(
      title: 'Conecte-se a um servidor',
      message: 'Vá em Conectar para adicionar e conectar a um servidor, depois volte aqui para ver e controlar os agendamentos.',
      actionLabel: 'Ir para Conectar',
      onAction: () => context.go(RouteNames.serverLogin),
    );
  }
}
