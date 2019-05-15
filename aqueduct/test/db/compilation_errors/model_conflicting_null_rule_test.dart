import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Delete rule of setNull throws exception if property is not nullable",
      () {
    try {
      ManagedDataModel([Owner, FailingChild]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message,
          contains("Relationship 'ref' on '_FailingChild' has both"));
    }
  });
}

class Owner extends ManagedObject<_Owner> implements _Owner {}

class _Owner {
  @primaryKey
  int id;

  FailingChild gen;
}

class FailingChild extends ManagedObject<_FailingChild>
    implements _FailingChild {}

class _FailingChild {
  @primaryKey
  int id;

  @Relate(Symbol('gen'), onDelete: DeleteRule.nullify, isRequired: true)
  Owner ref;
}
