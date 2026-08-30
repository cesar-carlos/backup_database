import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const Size kDesktopSurfaceSize = Size(1920, 1080);

Future<void> pumpDesktopSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(kDesktopSurfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
