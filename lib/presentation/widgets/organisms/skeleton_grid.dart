import 'package:backup_database/presentation/widgets/atoms/app_shimmer.dart';
import 'package:backup_database/presentation/widgets/molecules/skeleton_list_item.dart';
import 'package:flutter/widgets.dart';

/// **Organism** — vertical stack of [SkeletonListItem] under [AppShimmer].
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({
    required this.rowCount,
    super.key,
    this.padding = EdgeInsets.zero,
  });

  final int rowCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: AppShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List<Widget>.generate(
            rowCount,
            (_) => const SkeletonListItem(),
          ),
        ),
      ),
    );
  }
}
