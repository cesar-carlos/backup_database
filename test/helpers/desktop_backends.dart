// Test-only backends allow asynchronous fault injection without native DLLs.
import 'package:backup_database/presentation/managers/desktop_tray_backend.dart'
    as tray;
import 'package:backup_database/presentation/managers/desktop_window_backend.dart'
    as window;
import 'package:backup_database/presentation/managers/tray_manager_service.dart';
import 'package:backup_database/presentation/managers/window_manager_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void installDesktopBackends() {
  setUp(() {
    WindowManagerService().backendOverride = ChannelWindowBackend();
    TrayManagerService().backendOverride = ChannelTrayBackend();
  });
  tearDown(() {
    WindowManagerService().backendOverride = null;
    TrayManagerService().backendOverride = null;
  });
}

class ChannelWindowBackend extends Fake implements window.WindowBackend {
  static const channel = MethodChannel('window_manager');
  @override
  final List<window.WindowEvents> listeners = [];
  @override
  void addListener(window.WindowEvents listener) => listeners.add(listener);
  @override
  void removeListener(window.WindowEvents listener) =>
      listeners.remove(listener);
  @override
  Future<void> waitUntilReadyToShow([
    window.WindowSetup? options,
    VoidCallback? callback,
  ]) async {
    await channel.invokeMethod<void>('waitUntilReadyToShow');
    await channel.invokeMethod<void>('setTitleBarStyle', {
      'titleBarStyle': options?.titleBarStyle.name,
      'windowButtonVisibility': options?.windowButtonVisibility,
    });
    callback?.call();
  }

  @override
  Future<void> show({bool inactive = false}) =>
      channel.invokeMethod<void>('show', {'inactive': inactive});
  @override
  Future<void> maximize({bool vertically = false}) =>
      channel.invokeMethod<void>('maximize');
  @override
  Future<void> setMinimumSize(Size size) => channel.invokeMethod<void>(
    'setMinimumSize',
    {'width': size.width, 'height': size.height},
  );
  @override
  Future<void> ensureInitialized() =>
      channel.invokeMethod<void>('ensureInitialized');
  @override
  Future<void> hide() => channel.invokeMethod<void>('hide');
  @override
  Future<void> focus() => channel.invokeMethod<void>('focus');
  @override
  Future<void> restore() => channel.invokeMethod<void>('restore');
  @override
  Future<void> minimize() => channel.invokeMethod<void>('minimize');
  @override
  Future<void> unmaximize() => channel.invokeMethod<void>('unmaximize');
  @override
  Future<void> close() => channel.invokeMethod<void>('close');
  @override
  Future<bool> isVisible() async =>
      await channel.invokeMethod<bool>('isVisible') ?? false;
  @override
  Future<bool> isMinimized() async =>
      await channel.invokeMethod<bool>('isMinimized') ?? false;
  @override
  Future<bool> isMaximized() async =>
      await channel.invokeMethod<bool>('isMaximized') ?? false;
  @override
  Future<bool> isFocused() async =>
      await channel.invokeMethod<bool>('isFocused') ?? false;
  @override
  Future<void> setPreventClose(bool isPreventClose) =>
      channel.invokeMethod<void>('setPreventClose', {
        'isPreventClose': isPreventClose,
      });
  @override
  Future<void> setSkipTaskbar(bool isSkipTaskbar) => channel.invokeMethod<void>(
    'setSkipTaskbar',
    {'isSkipTaskbar': isSkipTaskbar},
  );
  @override
  Future<void> setTitle(String title) =>
      channel.invokeMethod<void>('setTitle', {'title': title});
}

class ChannelTrayBackend extends Fake implements tray.TrayBackend {
  static const channel = MethodChannel('tray_manager');
  @override
  void addListener(tray.TrayEvents listener) {}
  @override
  void removeListener(tray.TrayEvents listener) {}
  @override
  Future<void> setIcon(String path) =>
      channel.invokeMethod<void>('setIcon', {'iconPath': path});
  @override
  Future<void> setToolTip(String toolTip) =>
      channel.invokeMethod<void>('setToolTip', {'toolTip': toolTip});
  @override
  Future<void> setContextMenu(tray.TrayMenu menu) =>
      channel.invokeMethod<void>('setContextMenu', menu.toJson());
  @override
  Future<void> popUpContextMenu() =>
      channel.invokeMethod<void>('popUpContextMenu');
  @override
  Future<void> destroy() => channel.invokeMethod<void>('destroy');
}
