import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Model with Relationship and Column fails compilation", () {
    try {
      ManagedDataModel([InvalidMetadata, InvalidMetadata1]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message, contains("cannot both have"));
      expect(e.message, contains("InvalidMetadata"));
      expect(e.message, contains("'bar'"));
    }
  });
}

class InvalidMetadata extends ManagedObject<_InvalidMetadata> {}

class _InvalidMetadata {
  @Column(primaryKey: true)
  int id;

  @Relate(Symbol('foo'))
  @Column(indexed: true)
  InvalidMetadata1 bar;
}

class InvalidMetadata1 extends ManagedObject<_InvalidMetadata1> {}

class _InvalidMetadata1 {
  @primaryKey
  int id;

  InvalidMetadata foo;
}
