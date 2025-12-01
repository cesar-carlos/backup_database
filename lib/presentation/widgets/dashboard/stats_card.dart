import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class StatsCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData? icon;
  final String? iconSvg;
  final Color? color;

  const StatsCard({
    super.key,
    required this.title,
    required this.value,
    this.icon,
    this.iconSvg,
    this.color,
  }) : assert(
         icon != null || iconSvg != null,
         'Either icon or iconSvg must be provided',
       );

  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
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
                  child: iconSvg != null
                      ? SvgPicture.asset(
                          iconSvg!,
                          width: 28,
                          height: 28,
                          colorFilter: ColorFilter.mode(
                            cardColor,
                            BlendMode.srcIn,
                          ),
                        )
                      : Icon(icon, color: cardColor, size: 28),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
