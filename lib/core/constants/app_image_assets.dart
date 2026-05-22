/// Raster and ICO paths under [assets/image/new/] (see pubspec assets).
abstract final class AppImageAssets {
  static const String root = 'assets/image/new/';

  static const String database128 = '${root}database_128px.png';

  /// Launcher / exe icon source (not listed in Flutter assets — build-time only).
  static const String database512 = '${root}database_512px.png';

  /// System tray (Windows). Release build copies `app_icon.ico` here unless
  /// [trayIconCustomMarker] exists in the project tree.
  static const String trayIco = '${root}app_tray.ico';

  static const String trayIconCustomMarkerFile = '.tray_icon_custom';

  /// Empty marker file: when present, `build_installer.py` does not overwrite [trayIco].
  static const String trayIconCustomMarker = '$root$trayIconCustomMarkerFile';
}
