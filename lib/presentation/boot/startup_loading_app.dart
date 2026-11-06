import 'package:fluent_ui/fluent_ui.dart';

/// Visible feedback while server services and authentication initialize.
class StartupLoadingApp extends StatelessWidget {
  const StartupLoadingApp({super.key});

  @override
  Widget build(BuildContext context) => const FluentApp(
    debugShowCheckedModeBanner: false,
    home: ScaffoldPage(
      content: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressRing(),
            SizedBox(height: 20),
            Text('Inicializando Backup Database…'),
          ],
        ),
      ),
    ),
  );
}
