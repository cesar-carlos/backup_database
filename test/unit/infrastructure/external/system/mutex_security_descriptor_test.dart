import 'package:backup_database/infrastructure/external/system/mutex_security_descriptor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pipe SDDL keeps SY BA IU and adds the batch logon SID', () {
    const sddl = Win32SecurityDescriptor.namedPipeEveryoneGenericAllSddl;

    expect(sddl, contains('(A;;GRGW;;;SY)'));
    expect(sddl, contains('(A;;GRGW;;;BA)'));
    expect(sddl, contains('(A;;GRGW;;;IU)'));
    expect(sddl, contains('(A;;GRGW;;;S-1-5-3)'));
    expect(sddl.contains(';;;WD)'), isFalse);
    expect(sddl.contains(';;GA;'), isFalse);
  });
}
