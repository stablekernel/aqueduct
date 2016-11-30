import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import '../helpers.dart';

main() {
  setUpAll(() {
    var ps = new DefaultPersistentStore();
    ManagedDataModel dm = new ManagedDataModel([TestModel]);
    ManagedContext _ = new ManagedContext(dm, ps);
  });

  test("Accessing valueObject of Query automatically creates an instance", () {
    var q = new Query<TestModel>()..values.id = 1;

    expect(q.values.id, 1);
  });
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @managedPrimaryKey
  int id;

  String name;
}
