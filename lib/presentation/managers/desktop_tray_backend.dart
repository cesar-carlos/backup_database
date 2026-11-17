import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart' as native;

mixin TrayEvents {
  void onTrayIconMouseDown() {}
  void onTrayIconMouseUp() {}
  void onTrayIconRightMouseDown() {}
  void onTrayIconRightMouseUp() {}
  void onTrayMenuItemClick(TrayMenuItem menuItem) {}
}

class TrayMenuItem {
  const TrayMenuItem({required this.key, required this.label})
    : separator = false;
  const TrayMenuItem.separator() : key = null, label = '', separator = true;
  final String? key;
  final String label;
  final bool separator;
}

class TrayMenu {
  const TrayMenu({required this.items});
  final List<TrayMenuItem> items;
  Map<String, Object?> toJson() => {
    'items': [
      for (final item in items)
        {
          'key': item.key,
          'label': item.label,
          'type': item.separator ? 'separator' : 'normal',
        },
    ],
  };
}

class TrayBackend {
  native.TrayIcon? _tray;
  native.Image? _image;
  native.ListenerId? _listener;
  _NativeMenu? _menu;
  final _listeners = <TrayEvents>[];

  native.TrayIcon get _target {
    final tray = _tray ??=
        native.TrayIcon.create() ??
        (throw StateError('Não foi possível criar a bandeja'));
    _listener ??= tray.addListener((event) {
      for (final listener in List<TrayEvents>.of(_listeners)) {
        if (!_listeners.contains(listener)) continue;
        if (event is native.TrayIconClickedEvent) {
          listener.onTrayIconMouseUp();
        } else if (event is native.TrayIconRightClickedEvent) {
          listener.onTrayIconRightMouseDown();
        }
      }
    });
    return tray;
  }

  void addListener(TrayEvents listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void removeListener(TrayEvents listener) => _listeners.remove(listener);
  Future<void> setIcon(String path) async {
    final image =
        native.Image.fromFile(path) ?? native.ImageAsset.fromAsset(path);
    if (image == null) {
      throw StateError('Não foi possível carregar ícone: $path');
    }
    try {
      _target.icon = image;
      _target.setVisible(true);
    } on Object {
      image.dispose();
      rethrow;
    }
    _image?.dispose();
    _image = image;
  }

  Future<void> setToolTip(String value) async {
    _target.setTooltip(value);
  }

  Future<void> setContextMenu(TrayMenu model) async {
    final next = _NativeMenu(model, (item) {
      for (final listener in List<TrayEvents>.of(_listeners)) {
        if (_listeners.contains(listener)) listener.onTrayMenuItemClick(item);
      }
    });
    try {
      _target.setContextMenu(next.menu);
      if (Platform.isLinux) {
        _target.setContextMenuTrigger(native.ContextMenuTrigger.rightClicked);
      }
    } on Object {
      next.dispose();
      rethrow;
    }
    final previous = _menu;
    _menu = next;
    // Native callbacks may still be using the old menu on this event-loop turn.
    if (previous != null) Timer.run(previous.dispose);
  }

  Future<void> popUpContextMenu() async {
    _target.openContextMenu();
  }

  Future<void> destroy() async {
    final tray = _tray;
    if (_listener != null) tray?.removeListener(_listener!);
    _listener = null;
    tray?.setContextMenu(null);
    tray?.dispose();
    _tray = null;
    _image?.dispose();
    _image = null;
    final menu = _menu;
    _menu = null;
    if (menu != null) Timer.run(menu.dispose);
  }
}

class _NativeMenu {
  _NativeMenu(TrayMenu model, void Function(TrayMenuItem) clicked) {
    try {
      for (final entry in model.items) {
        if (entry.separator) {
          menu.addSeparator();
          continue;
        }
        final item =
            native.MenuItem.createWithLabelAndType(
              entry.label,
              native.MenuItemType.normal,
            ) ??
            (throw StateError('Não foi possível criar item da bandeja'));
        final id = item.addListener((event) {
          if (event is native.MenuItemClickedEvent) clicked(entry);
        });
        _items.add((item, id));
        menu.addItem(item);
      }
    } on Object {
      dispose();
      rethrow;
    }
  }
  final native.Menu menu =
      native.Menu.create() ?? (throw StateError('Menu nativo indisponível'));
  final _items = <(native.MenuItem, native.ListenerId)>[];
  void dispose() {
    for (final (item, id) in _items) {
      item.removeListener(id);
    }
    menu.dispose();
    for (final (item, _) in _items) {
      item.dispose();
    }
    _items.clear();
  }
}

final desktopTrayBackend = TrayBackend();
