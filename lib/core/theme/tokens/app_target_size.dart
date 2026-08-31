class AppTargetSize {
  AppTargetSize._();

  /// WCAG 2.2 AA 2.5.8 minimum target (logical pixels).
  static const double minimum = 24;

  /// WinUI / Fluent standard control height.
  static const double desktop = 32;

  /// Slightly larger target for spacious density.
  static const double spacious = 36;

  /// Alias of [desktop] for existing call sites.
  static const double comfortable = desktop;
}
