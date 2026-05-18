import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — centered progress ring with optional status message.
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
            const SizedBox(height: AppSpacing.md),
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
