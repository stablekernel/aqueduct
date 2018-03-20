import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

import '../../helpers.dart';

void main() {
  group("Or", () {
    ManagedContext context;

    setUpAll(() async {
      context = await contextWithModels([Model]);
      for (int i = 0; i < 10; i++) {
        await (new Query<Model>(context)
              ..values.id = i + 1
              ..values.name = "${i + 1}"
              ..values.timestamp = new DateTime(2001 + i))
            .insert();
      }
    });

    tearDownAll(() async {
      await context?.close();
      context = null;
    });

    test("Can use OR on same field", () async {
      // id == 1 || id == 5
      final q = new Query<Model>(context)
        ..sortBy((o) => o.id, QuerySortOrder.ascending)
        ..where((o) => o.id).equalTo(1).or((o) => o.id).equalTo(5);
      final results = await q.fetch();
      expect(results.length, 2);
      expect(results.first.id, 1);
      expect(results.last.id, 5);
    });

    test("Can use OR on different fields", () async {
      // id == 1 || name == "2"
      final q = new Query<Model>(context)
        ..sortBy((o) => o.id, QuerySortOrder.ascending)
        ..where((o) => o.id).equalTo(1).or((o) => o.name).equalTo("2");
      final results = await q.fetch();
      expect(results.length, 2);
      expect(results.first.id, 1);
      expect(results.last.id, 2);
    });

    test("Can use three fields in OR", () async {
      // id == 1 || name == "2" || timestamp == 2003
      final q = new Query<Model>(context)
        ..sortBy((o) => o.id, QuerySortOrder.ascending)
        ..where((o) => o.id)
            .equalTo(1)
            .or((o) => o.name)
            .equalTo("2")
            .or((o) => o.timestamp)
            .equalTo(new DateTime(2003));
      final results = await q.fetch();

      expect(results.length, 3);
      expect(results[0].id, 1);
      expect(results[1].id, 2);
      expect(results[2].id, 3);
    });

    test("Inversion operator only applies to next expression, not any other in OR", () async {
      // id == 1 || !(name < "9")
      final q = new Query<Model>(context)
        ..sortBy((o) => o.id, QuerySortOrder.ascending)
        ..where((o) => o.id).equalTo(1)
            .or((o) => o.name).not.lessThan("9");
      final results = await q.fetch();
      expect(results.length, 2);
      expect(results.first.id, 1);
      expect(results.last.id, 10);
    });

    test("If two WHERE clauses, OR only applies to the clause that contains it in its builder", () async {
      // id < 5 && (name == "1" || id >= 4)
      final q = new Query<Model>(context)
        ..sortBy((o) => o.id, QuerySortOrder.ascending)
        ..where((o) => o.id).lessThan(5)
        ..where((o) => o.name).equalTo("1").or((o) => o.id).greaterThanEqualTo(4);
      final results = await q.fetch();
      expect(results.length, 2);
      expect(results.first.id, 1);
      expect(results.last.id, 4);
    });
  });
}

class _Model {
  @Column(primaryKey: true)
  int id;

  String name;

  DateTime timestamp;
}

class Model extends ManagedObject<_Model> implements _Model {}
