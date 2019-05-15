import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

class InvalidModel extends ManagedObject<_InvalidModel>
    implements _InvalidModel {}

class _InvalidModel {
  @primaryKey
  int id;

  Uri uri;
}

void main() {
  test("Model with unsupported property type fails on compilation", () {
    try {
      ManagedDataModel([InvalidModel]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message, contains("'_InvalidModel'"));
      expect(e.message, contains("'uri'"));
      expect(e.message, contains("unsupported type"));
    }
  });
}
