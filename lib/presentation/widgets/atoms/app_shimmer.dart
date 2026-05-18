import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/app_duration.dart';
import 'package:backup_database/presentation/providers/skeleton_loading_preference_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

/// **Atom** — themed shimmer wrapper; respects [SkeletonLoadingPreferenceProvider].
class AppShimmer extends StatelessWidget {
  const AppShimmer({
    required this.child,
    super.key,
    this.period = AppDuration.shimmer,
  });

  final Widget child;
  final Duration period;

  static bool _shimmerEnabled(BuildContext context) {
    try {
      return context
          .watch<SkeletonLoadingPreferenceProvider>()
          .shimmerLoadingEffectsEnabled;
    } on ProviderNotFoundException {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = colors.surfaceVariant;
    final highlight = Color.lerp(base, colors.surface, 0.45)!;
    final enabled = _shimmerEnabled(context);
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: period,
      enabled: enabled,
      child: child,
    );
  }
}
