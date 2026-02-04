/// Interface for displaying native Windows message boxes.
abstract class IWindowsMessageBox {
  /// Shows a warning message box.
  void showWarning(String title, String message);

  /// Shows an informational message box.
  void showInfo(String title, String message);

  /// Shows an error message box.
  void showError(String title, String message);
}
