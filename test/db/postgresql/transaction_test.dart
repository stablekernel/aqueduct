import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

import '../../context_helpers.dart';

void main() {
  ManagedContext context;
  setUp(() async {
    context = await contextWithModels([Model]);
  });

  tearDown(() async {
    await context.close();
  });

  test("Queries in transaction block are executed in transaction", () async {
    await context.transaction((t) async {
      final q1 = new Query<Model>(t)..values.name = "Bob";
      await q1.insert();

      await Query.insertObject(t, new Model()..name = "Fred");
    });

    final objects = await (new Query<Model>(context)..sortBy((o) => o.name, QuerySortOrder.ascending)).fetch();
    expect(objects.length, 2);
    expect(objects.first.name, "Bob");
    expect(objects.last.name, "Fred");
  });

  test("A transaction returns null if it completes successfully", () async {
    final result = await context.transaction((t) async {
      await Query.insertObject(t, new Model()..name = "Bob");
    });

    expect(result, isNull);
  });

  test(
      "Queries outside of transaction block while transaction block is running are queued until transaction is complete",
      () async {
    context.transaction((t) async {
      await Query.insertObject(t, new Model()..name = "1");
      await Query.insertObject(t, new Model()..name = "2");
      await Query.insertObject(t, new Model()..name = "3");
    });

    final results = await (new Query<Model>(context)).fetch();
    expect(results.length, 3);
  });

  test("Error thrown from query rolls back transaction and is thrown by transaction method", () async {
    try {
      await context.transaction((t) async {
        await Query.insertObject(t, new Model()..name = "1");
        // This query will fail because name is null
        await Query.insertObject(t, new Model());
        fail('unreachable');
      });
      fail('unreachable');
    } on QueryException catch (e) {
      expect(e.toString(), contains("not-null"));
    }

    expect((await (new Query<Model>(context).fetch())).length, 0);
  });

  test("Error thrown from non-query code in transaction rolls back transaction and thrown by transaction method",
      () async {
    try {
      await context.transaction((t) async {
        await Query.insertObject(t, new Model()..name = "1");
        throw new StateError("hello");
      });
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(), contains("hello"));
    }

    expect((await (new Query<Model>(context).fetch())).length, 0);
  });

  test("A thrown rollback rolls back transaction and returns rollback reason", () async {
    final res = await context.transaction((t) async {
      final res = await Query.insertObject(t, new Model()..name = "1");

      if (res.name == "1") {
        throw new Rollback("hello");
      }

      await Query.insertObject(t, new Model()..name = "2");
    });

    expect(res, "hello");
    expect((await (new Query<Model>(context).fetch())).length, 0);
  });

  test("Queries executed through persistentStore.execute use transaction context", () async {
    await context.transaction((t) async {
      await Query.insertObject(t, new Model()..name = "1");
      await t.persistentStore.execute("INSERT INTO _Model (name) VALUES ('2')");
      await Query.insertObject(t, new Model()..name = "3");
    });

    expect((await (new Query<Model>(context).fetch())).length, 3);
  });

  test("Query on origional context within transaction block times out and cancels transaction", () async {
    try {
      await context.transaction((t)
      async {
        await Query.insertObject(t, new Model()..name = "1");
        final q = new Query<Model>(context)
          ..timeoutInSeconds = 1
          ..values.name = '2';
        await q.insert();
        await Query.insertObject(t, new Model()..name = "3");
      });
      fail('unreachable');
    } on QueryException catch (e) {
      expect(e.toString(), contains("timed out"));
    }

    final q = new Query<Model>(context);
    expect(await q.fetch(), isEmpty);
  });
}

class _Model {
  @primaryKey
  int id;

  String name;
}

class Model extends ManagedObject<_Model> implements _Model {}
