import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — padded vertical stack for standard page bodies.
class PageContentLayout extends StatelessWidget {
  const PageContentLayout({
    required this.children,
    super.key,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
