import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Duplicate inverse properties fail compilation", () {
    try {
      ManagedDataModel([DupInverse, DupInverseHas]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message, contains("has multiple relationship properties"));
      expect(e.message, contains("'inverse'"));
      expect(e.message, contains("foo, bar"));
    }
  });
}

class DupInverseHas extends ManagedObject<_DupInverseHas> {}

class _DupInverseHas {
  @primaryKey
  int id;

  ManagedSet<DupInverse> inverse;
}

class DupInverse extends ManagedObject<_DupInverse> {}

class _DupInverse {
  @primaryKey
  int id;

  @Relate(Symbol('inverse'))
  DupInverseHas foo;

  @Relate(Symbol('inverse'))
  DupInverseHas bar;
}
