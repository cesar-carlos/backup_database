import 'package:flutter/widgets.dart';

class AppZIndex {
  AppZIndex._();

  static const int base = 0;
  static const int dropdown = 100;
  static const int tooltip = 200;
  static const int modal = 300;
  static const int snackbar = 400;
  static const int notification = 500;

  static Widget stackByZIndex(
    List<({int zIndex, Widget child})> layers, {
    AlignmentGeometry alignment = AlignmentDirectional.topStart,
    StackFit fit = StackFit.loose,
    Clip clipBehavior = Clip.hardEdge,
  }) {
    final sorted = [...layers]..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return Stack(
      alignment: alignment,
      fit: fit,
      clipBehavior: clipBehavior,
      children: sorted.map((e) => e.child).toList(),
    );
  }
}
