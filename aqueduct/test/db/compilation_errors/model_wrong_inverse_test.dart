import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Managed objects with missing inverses fail compilation", () {
    try {
      ManagedDataModel([MissingInverse1, MissingInverseWrongSymbol]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message, contains("has no inverse property"));
      expect(e.message, contains("'_MissingInverseWrongSymbol'"));
      expect(e.message, contains("'has'"));
    }
  });
}

class MissingInverse1 extends ManagedObject<_MissingInverse1> {}

class _MissingInverse1 {
  @primaryKey
  int id;

  MissingInverseWrongSymbol inverse;
}

class MissingInverseWrongSymbol
    extends ManagedObject<_MissingInverseWrongSymbol> {}

class _MissingInverseWrongSymbol {
  @primaryKey
  int id;

  @Relate(Symbol('foobar'))
  MissingInverse1 has;
}
