import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

class NoPrimaryKey extends ManagedObject<_NoPrimaryKey>
    implements _NoPrimaryKey {}

class _NoPrimaryKey {
  String foo;
}

void main() {
  test("Entity without primary key fails", () {
    try {
      ManagedDataModel([NoPrimaryKey]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(
          e.message,
          contains(
              "Class '_NoPrimaryKey' doesn't declare a primary key property"));
    }
  });
}
