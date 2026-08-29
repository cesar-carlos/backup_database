abstract class LicenseSignatureVerifier {
  bool verify({
    required List<int> messageBytes,
    required List<int> signatureBytes,
  });
}
