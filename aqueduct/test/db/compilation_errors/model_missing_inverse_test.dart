import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

class MissingInverse2 extends ManagedObject<_MissingInverse2> {}

class _MissingInverse2 {
  @primaryKey
  int id;

  ManagedSet<MissingInverseAbsent> inverseMany;
}

class MissingInverseAbsent extends ManagedObject<_MissingInverseAbsent> {}

class _MissingInverseAbsent {
  @primaryKey
  int id;
}

void main() {
  test("Managed objects with missing inverses fail compilation", () {
    try {
      ManagedDataModel([MissingInverse2, MissingInverseAbsent]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message, contains("'_MissingInverse2'"));
      expect(e.message, contains("'inverseMany'"));
    }
  });
}
