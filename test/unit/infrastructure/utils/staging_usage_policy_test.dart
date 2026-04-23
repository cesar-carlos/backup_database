import 'package:backup_database/infrastructure/utils/staging_usage_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StagingUsagePolicy', () {
    test('ok abaixo de warn', () {
      expect(
        StagingUsagePolicy.levelFor(0),
        StagingUsageLevel.ok,
      );
      expect(
        StagingUsagePolicy.levelFor(StagingUsagePolicy.warnThresholdBytes - 1),
        StagingUsageLevel.ok,
      );
    });

    test('warn entre 5 GiB e 10 GiB', () {
      expect(
        StagingUsagePolicy.levelFor(StagingUsagePolicy.warnThresholdBytes),
        StagingUsageLevel.warn,
      );
      expect(
        StagingUsagePolicy.levelFor(StagingUsagePolicy.blockThresholdBytes - 1),
        StagingUsageLevel.warn,
      );
    });

    test('block a partir de 10 GiB', () {
      expect(
        StagingUsagePolicy.levelFor(StagingUsagePolicy.blockThresholdBytes),
        StagingUsageLevel.block,
      );
      expect(StagingUsagePolicy.shouldBlock(
        StagingUsagePolicy.blockThresholdBytes,
      ), isTrue);
    });
  });
}
