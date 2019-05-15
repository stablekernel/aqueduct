import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Cannot have only named constructor", () {
    try {
      ManagedDataModel([HasNoDefaultConstructor]);
      fail('unreachable');
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("HasNoDefaultConstructor"));
      expect(e.toString(), contains("default, unnamed constructor"));
    }
  });
}

class HasNoDefaultConstructor extends ManagedObject<_ConstructorTableDef> {
  HasNoDefaultConstructor.foo();
}

class _ConstructorTableDef {
  @primaryKey
  int id;
}
