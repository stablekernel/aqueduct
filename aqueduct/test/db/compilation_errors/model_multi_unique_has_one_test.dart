import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test(
      "Add Table to table definition with has- property in unique list throws exception",
      () {
    try {
      ManagedDataModel([
        MultiUniqueFailureRelationship,
        MultiUniqueFailureRelationshipInverse
      ]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message, contains("declares 'a' as unique"));
    }
  });
}

class MultiUniqueFailureRelationship
    extends ManagedObject<_MultiUniqueFailureRelationship> {}

@Table.unique([Symbol('a'), Symbol('b')])
class _MultiUniqueFailureRelationship {
  @primaryKey
  int id;

  MultiUniqueFailureRelationshipInverse a;
  int b;
}

class MultiUniqueFailureRelationshipInverse
    extends ManagedObject<_MultiUniqueFailureRelationshipInverse> {}

class _MultiUniqueFailureRelationshipInverse {
  @primaryKey
  int id;

  @Relate(Symbol('a'))
  MultiUniqueFailureRelationship rel;
}
