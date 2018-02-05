import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  ManagedContext context;
  setUp(() async {
    context = await contextWithModels([Obj]);
  });

  tearDown(() async {
    await context?.persistentStore?.close();
    context = null;
  });

  test("Can insert document object", () async {
    final q = new Query<Obj>()
        ..values.document = new Document.from({"k": "v"});
    final o = await q.insert();
    expect(o.document.data, {"k":"v"});
  });

  test("Can insert document array", () async {
    final q = new Query<Obj>()
      ..values.document = new Document.from([{"k": "v"}, 1]);
    final o = await q.insert();
    expect(o.document.data, [{"k":"v"}, 1]);
  });

  test("Can fetch document object", () async {
    final q = new Query<Obj>()
      ..values.document = new Document.from({"k": "v"});
    await q.insert();

    final o = await (new Query<Obj>()).fetch();
    expect(o.first.document.data, {"k":"v"});
  });

  test("Can fetch array object", () async {
    final q = new Query<Obj>()
      ..values.document = new Document.from([{"k": "v"}, 1]);
    await q.insert();

    final o = await (new Query<Obj>()).fetch();
    expect(o.first.document.data, [{"k":"v"}, 1]);
  });

  test("Can update value of document property", () async {
    final q = new Query<Obj>()
      ..values.document = new Document.from({"k": "v"});
    final o = await q.insert();

    final u = new Query<Obj>()
      ..where.id = whereEqualTo(o.id)
      ..values.document = new Document.from(["a"]);
    final updated = await u.updateOne();
    expect(updated.document.data, ["a"]);
  });
}

class Obj extends ManagedObject<_Obj> implements _Obj {}
class _Obj {
  @primaryKey
  int id;

  Document document;
}