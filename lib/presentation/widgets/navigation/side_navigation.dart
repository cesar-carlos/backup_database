import 'package:backup_database/presentation/widgets/navigation/navigation_item.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SideNavigation extends StatelessWidget {
  const SideNavigation({
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });
  final List<NavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      pane: NavigationPane(
        selected: selectedIndex,
        items: items
            .asMap()
            .entries
            .map(
              (entry) => PaneItem(
                icon: Icon(entry.value.icon),
                body: Text(entry.value.label),
                onTap: () => onDestinationSelected(entry.key),
              ),
            )
            .toList(),
      ),
    );
  }
}
