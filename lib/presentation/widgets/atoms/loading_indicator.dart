import 'package:fluent_ui/fluent_ui.dart';

class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ProgressRing(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: FluentTheme.of(context).typography.body,
            ),
          ],
        ],
      ),
    );
  }
}
