sealed class FtpUploadOffsetDecision {
  const FtpUploadOffsetDecision();
}

class FtpUploadFullUpload extends FtpUploadOffsetDecision {
  const FtpUploadFullUpload();
}

class FtpUploadResume extends FtpUploadOffsetDecision {
  const FtpUploadResume(this.offset);
  final int offset;
}

class FtpUploadSkipAndValidate extends FtpUploadOffsetDecision {
  const FtpUploadSkipAndValidate();
}

FtpUploadOffsetDecision computeFtpUploadOffsetDecision(
  int remoteSize,
  int fileSize,
  bool supportsRestStream,
) {
  if (remoteSize > fileSize) {
    return const FtpUploadFullUpload();
  }
  if (remoteSize == fileSize) {
    return const FtpUploadSkipAndValidate();
  }
  if (remoteSize > 0 && supportsRestStream) {
    return FtpUploadResume(remoteSize);
  }
  if (remoteSize > 0 && !supportsRestStream) {
    return const FtpUploadFullUpload();
  }
  return const FtpUploadFullUpload();
}
