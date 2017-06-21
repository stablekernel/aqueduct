import 'dart:async';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';

void main() {
  List<Test> objects;
  ManagedContext ctx;
  setUpAll(() async {
    ctx = await contextWithModels([Test]);
    objects = await populate(ctx);

    /* Note that objects are sorted by id, and therefore all values are in sorted order */
    objects.sort((t1, t2) => t1.id.compareTo(t2.id));
  });

  tearDownAll(() async {
    await ctx.persistentStore.close();
  });

  group("Average", () {
    test("Average produces average for int type", () async {
      var q = new Query<Test>();
      var result = await q.fold.average((t) => t.i);
      expect(result, objects.fold(0, (p, n) => p + n.i) / objects.length);
    });

    test("Average produces average for double type", () async {
      var q = new Query<Test>();
      var result = await q.fold.average((t) => t.d);
      expect(result, objects.fold(0, (p, n) => p + n.d) / objects.length);
    });

    test("Average with predicate", () async {
      var q = new Query<Test>()
        ..where.id = whereLessThanEqualTo(5);
      var result = await q.fold.average((t) => t.i);
      expect(result, objects.sublist(0, 5).fold(0, (p, n) => p + n.i) / 5);
    });
  });

  group("Count", () {
    test("Count produces number of objects", () async {
      var q = new Query<Test>();
      var result = await q.fold.count();
      expect(result, objects.length);
    });

    test("Count with predicate", () async {
      var q = new Query<Test>()
        ..where.id = whereLessThanEqualTo(5);
      var result = await q.fold.count();
      expect(result, 5);
    });
  });

  group("Maximum", () {
    test("Maximum of int", () async {
      var q = new Query<Test>();
      var result = await q.fold.maximum((t) => t.i);
      expect(result, objects.last.i);
    });

    test("Maximum of double", () async {
      var q = new Query<Test>();
      var result = await q.fold.maximum((t) => t.d);
      expect(result, objects.last.d);
    });

    test("Maximum of String", () async {
      var q = new Query<Test>();
      var result = await q.fold.maximum((t) => t.s);
      expect(result, objects.last.s);
    });

    test("Maximum of DateTime", () async {
      var q = new Query<Test>();
      var result = await q.fold.maximum((t) => t.dt);
      expect(result, objects.last.dt);
    });

    test("Maximum with predicate", () async {
      var q = new Query<Test>()
        ..where.id = whereLessThanEqualTo(5);
      var result = await q.fold.maximum((t) => t.i);
      expect(result, objects[4].i);
    });
  });

  group("Minimum", () {
    test("Minimum of int", () async {
      var q = new Query<Test>();
      var result = await q.fold.minimum((t) => t.i);
      expect(result, objects.first.i);
    });

    test("Minimum of double", () async {
      var q = new Query<Test>();
      var result = await q.fold.minimum((t) => t.d);
      expect(result, objects.first.d);
    });

    test("Minimum of String", () async {
      var q = new Query<Test>();
      var result = await q.fold.minimum((t) => t.s);
      expect(result, objects.first.s);
    });

    test("Minimum of DateTime", () async {
      var q = new Query<Test>();
      var result = await q.fold.minimum((t) => t.dt);
      expect(result, objects.first.dt);
    });

    test("Minimum with predicate", () async {
      var q = new Query<Test>()
        ..where.id = whereGreaterThan(5);
      var result = await q.fold.minimum((t) => t.i);
      expect(result, objects[5].i);
    });
  });

  group("Sum", () {
    test("Sum produces sum for int type", () async {
      var q = new Query<Test>();
      var result = await q.fold.sum((t) => t.i);
      expect(result, objects.fold(0, (p, n) => p + n.i));
    });

    test("Sum produces sum for double type", () async {
      var q = new Query<Test>();
      var result = await q.fold.sum((t) => t.d);
      expect(result, objects.fold(0, (p, n) => p + n.d));
    });

    test("Sum with predicate", () async {
      var q = new Query<Test>()
        ..where.id = whereLessThanEqualTo(5);
      var result = await q.fold.sum((t) => t.i);
      expect(result, objects.sublist(0, 5).fold(0, (p, a) => p + a.i));
    });
  });
}

class Test extends ManagedObject<_Test> implements _Test {}
class _Test {
  @managedPrimaryKey
  int id;

  String s;
  DateTime dt;
  double d;
  int i;
}

Future<List<Test>> populate(ManagedContext ctx) async {
  var s = "a";
  var dt = new DateTime.now();
  var d = 0.0;
  var i = 0;

  return Future.wait(new List.generate(10, (_) {
    var q = new Query<Test>(ctx)
        ..values.s = s
        ..values.dt = dt
        ..values.d = d
        ..values.i = i;

    s += "a";
    dt = dt.add(new Duration(seconds: 10));
    d += 10.0;
    i += 10;

    return q.insert();
  }));
}