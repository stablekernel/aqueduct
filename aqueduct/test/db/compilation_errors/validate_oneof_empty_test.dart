import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

class FailingEmptyOneOf extends ManagedObject<_FEO> {}

class _FEO {
  @primaryKey
  int id;

  @Validate.oneOf([])
  int d;
}

void main() {
  test("Empty oneOf", () {
    try {
      ManagedDataModel([FailingEmptyOneOf]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("Validate.oneOf"));
      expect(e.toString(), contains("_FEO.d"));
    }
  });
}
