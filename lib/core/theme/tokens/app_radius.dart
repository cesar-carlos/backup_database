import 'package:flutter/widgets.dart';

class AppRadius {
  AppRadius._();

  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double pill = 999;

  static const BorderRadius circularSm = BorderRadius.all(
    Radius.circular(sm),
  );
  static const BorderRadius circularMd = BorderRadius.all(
    Radius.circular(md),
  );
  static const BorderRadius circularLg = BorderRadius.all(
    Radius.circular(lg),
  );
}
