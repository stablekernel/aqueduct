import 'dart:async';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  List<Test> objects;
  ManagedContext ctx;
  setUp(() async {
    ctx = await contextWithModels([Test]);
  });

  tearDown(() async {
    await ctx.close();
  });

  group("In transaction", () {
    setUp(() async {
      objects = await populate(ctx);

      /* Note that objects are sorted by id, and therefore all values are in sorted order */
      objects.sort((t1, t2) => t1.id.compareTo(t2.id));
    });

    test("Reduce functions work correctly in a tansaction", () async {
      int result;
      await ctx.transaction((t) async {
        await t.insertObject(Test()
          ..i = 1
          ..d = 2.0
          ..dt = DateTime.now()
          ..s = "x");
        var q = Query<Test>(t);
        result = await q.reduce.count();
      });

      expect(result, objects.length + 1);
      result = await Query<Test>(ctx).reduce.count();
      expect(result, objects.length + 1);
    });
  });

  group("Average", () {
    setUp(() async {
      objects = await populate(ctx);

      /* Note that objects are sorted by id, and therefore all values are in sorted order */
      objects.sort((t1, t2) => t1.id.compareTo(t2.id));
    });

    test("Average produces average for int type", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.average((t) => t.i);
      expect(result, objects.fold(0, (p, n) => p + n.i) / objects.length);
    });

    test("Average produces average for double type", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.average((t) => t.d);
      expect(result, objects.fold(0, (p, n) => p + n.d) / objects.length);
    });

    test("Average with predicate", () async {
      var q = Query<Test>(ctx)..where((p) => p.id).lessThanEqualTo(5);
      var result = await q.reduce.average((t) => t.i);
      expect(result, objects.sublist(0, 5).fold(0, (p, n) => p + n.i) / 5);
    });
  });

  group("Count", () {
    setUp(() async {
      objects = await populate(ctx);

      /* Note that objects are sorted by id, and therefore all values are in sorted order */
      objects.sort((t1, t2) => t1.id.compareTo(t2.id));
    });

    test("Count produces number of objects", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.count();
      expect(result, objects.length);
    });

    test("Count with predicate", () async {
      var q = Query<Test>(ctx)..where((p) => p.id).lessThanEqualTo(5);
      var result = await q.reduce.count();
      expect(result, 5);
    });
  });

  group("Maximum", () {
    setUp(() async {
      objects = await populate(ctx);

      /* Note that objects are sorted by id, and therefore all values are in sorted order */
      objects.sort((t1, t2) => t1.id.compareTo(t2.id));
    });

    test("Maximum of int", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.maximum((t) => t.i);
      expect(result, objects.last.i);
    });

    test("Maximum of double", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.maximum((t) => t.d);
      expect(result, objects.last.d);
    });

    test("Maximum of String", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.maximum((t) => t.s);
      expect(result, objects.last.s);
    });

    test("Maximum of DateTime", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.maximum((t) => t.dt);
      expect(result, objects.last.dt);
    });

    test("Maximum with predicate", () async {
      var q = Query<Test>(ctx)..where((p) => p.id).lessThanEqualTo(5);
      var result = await q.reduce.maximum((t) => t.i);
      expect(result, objects[4].i);
    });
  });

  group("Minimum", () {
    setUp(() async {
      objects = await populate(ctx);

      /* Note that objects are sorted by id, and therefore all values are in sorted order */
      objects.sort((t1, t2) => t1.id.compareTo(t2.id));
    });

    test("Minimum of int", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.minimum((t) => t.i);
      expect(result, objects.first.i);
    });

    test("Minimum of double", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.minimum((t) => t.d);
      expect(result, objects.first.d);
    });

    test("Minimum of String", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.minimum((t) => t.s);
      expect(result, objects.first.s);
    });

    test("Minimum of DateTime", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.minimum((t) => t.dt);
      expect(result, objects.first.dt);
    });

    test("Minimum with predicate", () async {
      var q = Query<Test>(ctx)..where((p) => p.id).greaterThan(5);
      var result = await q.reduce.minimum((t) => t.i);
      expect(result, objects[5].i);
    });
  });

  group("Sum", () {
    setUp(() async {
      objects = await populate(ctx);

      /* Note that objects are sorted by id, and therefore all values are in sorted order */
      objects.sort((t1, t2) => t1.id.compareTo(t2.id));
    });

    test("Sum produces sum for int type", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.sum((t) => t.i);
      expect(result, objects.fold(0, (p, n) => p + n.i));
    });

    test("Sum produces sum for double type", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.sum((t) => t.d);
      expect(result, objects.fold(0, (p, n) => p + n.d));
    });

    test("Sum with predicate", () async {
      var q = Query<Test>(ctx)..where((p) => p.id).lessThanEqualTo(5);
      var result = await q.reduce.sum((t) => t.i);
      expect(result, objects.sublist(0, 5).fold(0, (p, a) => p + a.i));
    });
  });

  group("Overflow", () {
    setUp(() async {
      objects = await populate(ctx, overflow: true);

      /* Note that objects are sorted by id, and therefore all values are in sorted order */
      objects.sort((t1, t2) => t1.id.compareTo(t2.id));
    });

    test("Sum with large integer numbers", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.sum((t) => t.i);
      expect(result, objects.fold(0, (p, n) => p + n.i));
    });

    test("Sum with fractional", () async {
      var q = Query<Test>(ctx);
      var result = await q.reduce.sum((t) => t.d);
      expect(result, objects.fold(0, (p, n) => p + n.d));
    });
  });
}

class Test extends ManagedObject<_Test> implements _Test {}

class _Test {
  @primaryKey
  int id;

  String s;
  DateTime dt;
  double d;
  int i;
}

Future<List<Test>> populate(ManagedContext ctx, {bool overflow = false}) async {
  var s = "a";
  var dt = DateTime.now();
  var d = 0.0;
  var i = 0;

  if (overflow) {
    d = 2.1234;
    i = 100000000000;
  }

  return Future.wait(List.generate(10, (_) {
    var q = Query<Test>(ctx)
      ..values.s = s
      ..values.dt = dt
      ..values.d = d
      ..values.i = i;

    s += "a";
    dt = dt.add(const Duration(seconds: 10));
    d += 10.0;
    i += 10;

    return q.insert();
  }));
}
