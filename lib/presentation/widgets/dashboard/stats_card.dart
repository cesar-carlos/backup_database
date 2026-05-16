import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:fluent_ui/fluent_ui.dart';

class StatsCard extends StatelessWidget {
  const StatsCard({
    required this.title,
    required this.value,
    required this.iconAsset,
    super.key,
    this.color,
  });
  final String title;
  final String value;
  final String iconAsset;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? AppPalette.primary;

    return Card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset(
                  iconAsset,
                  width: 28,
                  height: 28,
                  color: cardColor,
                  colorBlendMode: BlendMode.srcIn,
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: FluentTheme.of(
              context,
            ).typography.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(title, style: FluentTheme.of(context).typography.body),
        ],
      ),
    );
  }
}
