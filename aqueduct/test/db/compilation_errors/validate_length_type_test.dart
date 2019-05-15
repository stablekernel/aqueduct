import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

class FailingLength extends ManagedObject<_FLEN> {}

class _FLEN {
  @primaryKey
  int id;

  @Validate.length(equalTo: 6)
  int d;
}

void main() {
  test("Non-string Validate.length", () {
    try {
      ManagedDataModel([FailingLength]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("is only valid for 'String'"));
      expect(e.toString(), contains("_FLEN.d"));
    }
  });
}
