import 'package:fluent_ui/fluent_ui.dart';

class NavigationItem {
  const NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;
}
