import 'dart:async';
import 'dart:ui';

import 'package:window_manager/window_manager.dart' as native;

export 'package:window_manager/window_manager.dart' show TitleBarStyle;

/// Only the events consumed by the application's lifecycle policy.
mixin WindowEvents {
  FutureOr<void> onWindowClose() {}
  void onWindowMinimize() {}
  void onWindowFocus() {}
}

class WindowSetup {
  const WindowSetup({
    required this.size,
    required this.minimumSize,
    required this.center,
    required this.skipTaskbar,
    required this.title,
    required this.titleBarStyle,
    required this.windowButtonVisibility,
  });
  final Size size;
  final Size minimumSize;
  final bool center;
  final bool skipTaskbar;
  final String title;
  final native.TitleBarStyle titleBarStyle;
  final bool windowButtonVisibility;
}

/// Native calls remain asynchronous at this boundary for lifecycle serialization
/// and fault injection. Missing native windows fail instead of silently succeeding.
class WindowBackend {
  native.Window? _window;
  native.ListenerId? _listener;
  bool _preventClose = false;
  final List<WindowEvents> listeners = [];
  native.Window get _target => _window ??=
      native.WindowManager.instance.getCurrent() ??
      (throw StateError('Janela nativa indisponível'));

  Future<void> ensureInitialized() async {
    _wire();
  }

  void _wire() {
    _listener ??= _target.addListener((event) async {
      if (event is native.WindowCloseRequestedEvent && _preventClose) {
        event.request.cancel();
      }
      for (final listener in List<WindowEvents>.of(listeners)) {
        if (!listeners.contains(listener)) continue;
        if (event is native.WindowCloseRequestedEvent) {
          await listener.onWindowClose();
        } else if (event is native.WindowMinimizedEvent) {
          listener.onWindowMinimize();
        } else if (event is native.WindowFocusedEvent) {
          listener.onWindowFocus();
        }
      }
    });
  }

  void addListener(WindowEvents listener) {
    if (!listeners.contains(listener)) listeners.add(listener);
    _wire();
  }

  void removeListener(WindowEvents listener) {
    listeners.remove(listener);
    // Keep close interception active until process shutdown, even after UI
    // listeners are removed. Otherwise X can bypass resource cleanup.
    if (listeners.isEmpty && !_preventClose && _listener != null) {
      _target.removeListener(_listener!);
      _listener = null;
    }
  }

  Future<void> setPreventClose(bool value) async {
    _preventClose = value;
    _wire();
  }

  Future<void> waitUntilReadyToShow([
    WindowSetup? options,
    VoidCallback? callback,
  ]) async {
    if (options != null) {
      final window = _target;
      window.titleBarStyle = options.titleBarStyle;
      window.isWindowControlButtonsVisible = options.windowButtonVisibility;
      if (window.isFullScreen) window.isFullScreen = false;
      if (window.isMaximized) window.unmaximize();
      if (window.isMinimized) window.restore();
      window.setSize(options.size.toNative(), false);
      if (options.center) window.center();
      window.minimumSize = options.minimumSize.toNative();
      window.isVisibleInTaskbar = !options.skipTaskbar;
      window.title = options.title;
    }
    callback?.call();
  }

  Future<void> show({bool inactive = false}) async {
    if (_target.isMinimized) _target.restore();
    if (inactive) {
      _target.showInactive();
    } else {
      _target.show();
    }
  }

  Future<void> hide() async {
    _target.hide();
  }

  Future<void> focus() async {
    _target.focus();
  }

  Future<void> restore() async {
    _target.restore();
  }

  Future<void> minimize() async {
    _target.minimize();
  }

  Future<void> maximize({bool vertically = false}) async {
    _target.maximize();
  }

  Future<void> unmaximize() async {
    _target.unmaximize();
  }

  Future<void> close() async {
    _target.close();
  }

  Future<bool> isVisible() async => _target.isVisible;
  Future<bool> isMinimized() async => _target.isMinimized;
  Future<bool> isMaximized() async => _target.isMaximized;
  Future<bool> isFocused() async => _target.isFocused;
  Future<void> setMinimumSize(Size value) async {
    _target.minimumSize = value.toNative();
  }

  Future<void> setSkipTaskbar(bool value) async {
    _target.isVisibleInTaskbar = !value;
  }

  Future<void> setTitle(String value) async {
    _target.title = value;
  }
}

final desktopWindowBackend = WindowBackend();
