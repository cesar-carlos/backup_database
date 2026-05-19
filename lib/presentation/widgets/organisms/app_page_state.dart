import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum AppPageStateTone {
  neutral,
  info,
  warning,
  danger,
}

/// **Organism** - shared page/section state surface for loading, empty and
/// error states on management screens.
class AppPageState extends StatelessWidget {
  const AppPageState({
    required this.icon,
    required this.title,
    super.key,
    this.message,
    this.actionLabel,
    this.onAction,
    this.isLoading = false,
    this.tone = AppPageStateTone.neutral,
  });

  factory AppPageState.loading({
    required String title,
    String? message,
    Key? key,
  }) {
    return AppPageState(
      key: key,
      icon: FluentIcons.sync,
      title: title,
      message: message,
      isLoading: true,
    );
  }

  factory AppPageState.empty({
    required String title,
    String? message,
    String? actionLabel,
    VoidCallback? onAction,
    Key? key,
  }) {
    return AppPageState(
      key: key,
      icon: FluentIcons.inbox,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  factory AppPageState.error({
    required String title,
    String? message,
    String? actionLabel,
    VoidCallback? onAction,
    Key? key,
  }) {
    return AppPageState(
      key: key,
      icon: FluentIcons.error_badge,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      tone: AppPageStateTone.danger,
    );
  }

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isLoading;
  final AppPageStateTone tone;

  @override
  Widget build(BuildContext context) {
    final accentOrSemantic = _resolveColor(context);
    final useOnSurfaceForCopy =
        !isLoading && tone == AppPageStateTone.neutral;
    final titleIconColor = useOnSurfaceForCopy
        ? context.colors.onSurface
        : accentOrSemantic;
    final titleStyle = FluentTheme.of(
      context,
    ).typography.subtitle?.copyWith(color: titleIconColor);

    return Center(
      child: Padding(
        padding: AppSpacing.paddingLg,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: ProgressRing(
                    activeColor: accentOrSemantic,
                    strokeWidth: 3,
                  ),
                )
              else
                Icon(icon, size: 40, color: titleIconColor),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: titleStyle,
              ),
              if (message != null && message!.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: FluentTheme.of(context).typography.body?.copyWith(
                    color: useOnSurfaceForCopy
                        ? context.colors.onSurface
                        : null,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.lg),
                AppButton.icon(
                  icon: FluentIcons.chevron_right,
                  label: actionLabel!,
                  onPressed: onAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _resolveColor(BuildContext context) {
    final colors = context.colors;
    return switch (tone) {
      AppPageStateTone.neutral =>
        FluentTheme.of(context).accentColor.defaultBrushFor(
          FluentTheme.of(context).brightness,
        ),
      AppPageStateTone.info => colors.info,
      AppPageStateTone.warning => colors.warning,
      AppPageStateTone.danger => colors.danger,
    };
  }
}
