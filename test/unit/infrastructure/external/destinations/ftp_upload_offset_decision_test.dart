import 'package:backup_database/infrastructure/external/destinations/ftp_upload_offset_decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeFtpUploadOffsetDecision', () {
    test('returns FullUpload when remoteSize is 0', () {
      final decision = computeFtpUploadOffsetDecision(0, 1000, true);
      expect(decision, isA<FtpUploadFullUpload>());
    });

    test('returns FullUpload when remoteSize is 0 and REST not supported', () {
      final decision = computeFtpUploadOffsetDecision(0, 1000, false);
      expect(decision, isA<FtpUploadFullUpload>());
    });

    test('returns SkipAndValidate when remoteSize equals fileSize', () {
      final decision = computeFtpUploadOffsetDecision(1000, 1000, true);
      expect(decision, isA<FtpUploadSkipAndValidate>());
    });

    test('returns SkipAndValidate when remoteSize equals fileSize without REST',
        () {
      final decision = computeFtpUploadOffsetDecision(1000, 1000, false);
      expect(decision, isA<FtpUploadSkipAndValidate>());
    });

    test('returns Resume when 0 < remoteSize < fileSize and REST supported',
        () {
      final decision = computeFtpUploadOffsetDecision(500, 1000, true);
      expect(decision, isA<FtpUploadResume>());
      expect((decision as FtpUploadResume).offset, 500);
    });

    test('returns FullUpload when partial exists but REST not supported', () {
      final decision = computeFtpUploadOffsetDecision(500, 1000, false);
      expect(decision, isA<FtpUploadFullUpload>());
    });

    test('returns FullUpload when remoteSize > fileSize', () {
      final decision = computeFtpUploadOffsetDecision(1500, 1000, true);
      expect(decision, isA<FtpUploadFullUpload>());
    });

    test('returns Resume with correct offset for various partial sizes', () {
      expect(
        (computeFtpUploadOffsetDecision(1, 100, true) as FtpUploadResume)
            .offset,
        1,
      );
      expect(
        (computeFtpUploadOffsetDecision(99, 100, true) as FtpUploadResume)
            .offset,
        99,
      );
    });
  });
}
