import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.2 AA 2.5.8 target size (24×24) for Windows desktop controls.
const AccessibilityGuideline
desktopTapTargetGuideline = MinimumTapTargetGuideline(
  size: Size(24, 24),
  link: 'https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html',
);
