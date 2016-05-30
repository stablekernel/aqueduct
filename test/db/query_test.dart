import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

main() {
  var ps = new DefaultPersistentStore();
  DataModel dm = new DataModel([TestModel]);
  ModelContext _ = new ModelContext(dm, ps);

  test("Accessing valueObject of Query automatically creates an instance", () {
    var q = new Query<TestModel>()
        ..values.id = 1;

    expect(q.values.id, 1);
  });
}

class TestModel extends Model<_TestModel> implements _TestModel {}
class _TestModel {
  @primaryKey
  int id;

  String name;
}
