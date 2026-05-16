import 'package:flutter/animation.dart';

class AppCurves {
  AppCurves._();

  static const Curve standard = Curves.easeInOut;
  static const Curve decelerate = Curves.decelerate;
  static const Curve accelerate = Curves.fastOutSlowIn;
}
