import 'package:test/test.dart';
import 'package:monadart/monadart.dart';
import 'package:postgresql/postgresql.dart' as postgresql;

void main() {
  PostgresModelAdapter adapter;

  setUp(() {
    adapter = new PostgresModelAdapter(null, () async {
      var uri = 'postgres://dart:dart@localhost:5432/dart_test';
      return await postgresql.connect(uri);
    });
  });

  tearDown(() {
    adapter.close();
    adapter = null;
  });

  test("Updating existing object works", () async {
    await generateTemporarySchemaFromModels(adapter, [TestModel]);

    var m = new TestModel()
      ..name = "Bob"
      ..emailAddress = "1@a.com";

    var req = new Query<TestModel>()..valueObject = m;
    await req.insert(adapter);

    m
      ..name = "Fred"
      ..emailAddress = "2@a.com";

    req = new Query<TestModel>()
      ..predicate = new Predicate("name = @name", {"name": "Bob"})
      ..valueObject = m;

    var response = await req.update(adapter);
    var result = response.first;

    expect(result.name, "Fred");
    expect(result.emailAddress, "2@a.com");
  });

  test("Updating non-existant object fails", () async {});
}

@ModelBacking(TestModelBacking)
@proxy
class TestModel extends Object with Model implements TestModelBacking {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class TestModelBacking extends Model {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String name;

  @Attributes(nullable: true, unique: true)
  String emailAddress;
}
