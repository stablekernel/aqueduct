import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

class FailingOneOf extends ManagedObject<_FOO> {}

class _FOO {
  @primaryKey
  int id;

  @Validate.oneOf(["x", "y"])
  int d;
}

void main() {
  test("Non-matching type for oneOf", () {
    try {
      ManagedDataModel([FailingOneOf]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("Validate.oneOf"));
      expect(e.toString(), contains("_FOO.d"));
    }
  });
}
