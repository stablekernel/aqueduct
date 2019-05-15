import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test(
      "Add Table to table definition with only single element in unique list throws exception, warns to use Table",
      () {
    try {
      ManagedDataModel([MultiUniqueFailureSingleElement]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message,
          contains("add 'Column(unique: true)' to declaration of 'a'"));
    }
  });
}

class MultiUniqueFailureSingleElement
    extends ManagedObject<_MultiUniqueFailureSingleElement> {}

@Table.unique([Symbol('a')])
class _MultiUniqueFailureSingleElement {
  @primaryKey
  int id;

  int a;
}
