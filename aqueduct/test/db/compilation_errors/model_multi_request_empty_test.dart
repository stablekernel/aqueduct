import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Add Table to table definition with empty unique list throws exception",
      () {
    try {
      ManagedDataModel([MultiUniqueFailureNoElement]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message, contains("Must contain two or more attributes"));
    }
  });
}

class MultiUniqueFailureNoElement
    extends ManagedObject<_MultiUniqueFailureNoElement> {}

@Table.unique([])
class _MultiUniqueFailureNoElement {
  @primaryKey
  int id;
}
