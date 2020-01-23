import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  ManagedContext context;
  setUp(() async {
    context = await contextWithModels([Obj]);
  });

  tearDown(() async {
    await context?.close();
    context = null;
  });

  group("Basic queries", () {
    test("Can insert document object", () async {
      final q = Query<Obj>(context)
        ..values.id = 1
        ..values.document = Document({"k": "v"});
      final o = await q.insert();
      expect(o.document.data, {"k": "v"});
    });

    test("Can insert document array", () async {
      final q = Query<Obj>(context)
        ..values.id = 1
        ..values.document = Document([
          {"k": "v"},
          1
        ]);
      final o = await q.insert();
      expect(o.document.data, [
        {"k": "v"},
        1
      ]);
    });

    test("Can fetch document object", () async {
      final q = Query<Obj>(context)
        ..values.id = 1
        ..values.document = Document({"k": "v"});
      await q.insert();

      final o = await Query<Obj>(context).fetch();
      expect(o.first.document.data, {"k": "v"});
    });

    test("Can fetch array object", () async {
      final q = Query<Obj>(context)
        ..values.id = 1
        ..values.document = Document([
          {"k": "v"},
          1
        ]);
      await q.insert();

      final o = await Query<Obj>(context).fetch();
      expect(o.first.document.data, [
        {"k": "v"},
        1
      ]);
    });

    test("Can update value of document property", () async {
      final q = Query<Obj>(context)
        ..values.id = 1
        ..values.document = Document({"k": "v"});
      final o = await q.insert();

      final u = Query<Obj>(context)
        ..where((o) => o.id).equalTo(o.id)
        ..values.document = Document(["a"]);
      final updated = await u.updateOne();
      expect(updated.document.data, ["a"]);
    });
  });

  group("Sub-document selection", () {
    setUp(() async {
      final testData = [
        {"key": "value"}, // 1
        {
          "key": [1, 2]
        }, // 2
        {
          "key": {"innerKey": "value"}
        }, // 3
        [1, 2], // 4
        [
          {"1": "v1"},
          {"2": "v2"}
        ], // 5
        [
          {"1": []},
          {"2": "v2"},
          {"3": "v3"}
        ], // 6
        {"1": "v1", "2": "v2", "3": "v3"}, // 7
      ];

      var counter = 1;
      await Future.forEach(testData, (data) async {
        final q = Query<Obj>(context)
          ..values.id = counter
          ..values.document = Document(data);
        await q.insert();
        counter++;
      });
    });

    test("Can subscript top-level object and return primitive", () async {
      // {"key": "value"}
      var q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(1)
        ..returningProperties((obj) => [obj.id, obj.document["key"]]);
      var o = await q.fetchOne();
      expect(o.document.data, "value");

      q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(1)
        ..returningProperties((obj) => [obj.id, obj.document["unknownKey"]]);
      o = await q.fetchOne();
      expect(o.document, null);
    });

    test("Can subscript top-level object and return array", () async {
      // {"key": [1, 2]},
      var q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(2)
        ..returningProperties((obj) => [obj.id, obj.document["key"]]);
      var o = await q.fetchOne();
      expect(o.document.data, [1, 2]);
    });

    test("Can subscript top-level object and return object", () async {
      // {"key": {"innerKey": "value"}}
      final q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(3)
        ..returningProperties((obj) => [obj.id, obj.document["key"]]);
      final o = await q.fetchOne();
      expect(o.document.data, {"innerKey": "value"});
    });

    test("Can subscript top-level array and return indexed primitive",
        () async {
      // [1, 2],
      var q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(4)
        ..returningProperties((obj) => [obj.id, obj.document[0]]);
      var o = await q.fetchOne();
      expect(o.document.data, 1);

      q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(4)
        ..returningProperties((obj) => [obj.id, obj.document[1]]);
      o = await q.fetchOne();
      expect(o.document.data, 2);

      q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(4)
        ..returningProperties((obj) => [obj.id, obj.document[-1]]);
      o = await q.fetchOne();
      expect(o.document.data, 2);

      q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(4)
        ..returningProperties((obj) => [obj.id, obj.document[3]]);
      o = await q.fetchOne();
      expect(o.document, null);
    });

    test("Can subscript object and inner array", () async {
      // {"key": [1, 2]},
      var q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(2)
        ..returningProperties((obj) => [obj.id, obj.document["key"][0]]);
      var o = await q.fetchOne();
      expect(o.document.data, 1);

      q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(2)
        ..returningProperties((obj) => [obj.id, obj.document["foo"][0]]);
      o = await q.fetchOne();
      expect(o.document, null);

      q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(2)
        ..returningProperties((obj) => [obj.id, obj.document["key"][3]]);
      o = await q.fetchOne();
      expect(o.document, null);
    });

    test("Can subscript array and inner object", () async {
      // [{"1": "v1"}, {"2": "v2"}]
      var q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(5)
        ..returningProperties((obj) => [obj.id, obj.document[0]["1"]]);
      var o = await q.fetchOne();
      expect(o.document.data, "v1");

      q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(5)
        ..returningProperties((obj) => [obj.id, obj.document[1]["2"]]);
      o = await q.fetchOne();
      expect(o.document.data, "v2");

      q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(5)
        ..returningProperties((obj) => [obj.id, obj.document[3]["2"]]);
      o = await q.fetchOne();
      expect(o.document, null);

      q = Query<Obj>(context)
        ..where((o) => o.id).equalTo(5)
        ..returningProperties((obj) => [obj.id, obj.document[0]["foo"]]);
      o = await q.fetchOne();
      expect(o.document, null);
    });
  });
}

class Obj extends ManagedObject<_Obj> implements _Obj {}

class _Obj {
  @Column(primaryKey: true)
  int id;

  Document document;
}
