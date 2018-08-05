import 'dart:async';

import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  final harness = HarnessSubclass()..install();

  test("afterStart that invokes resetData sets up database and invokes seed",
      () async {
    final q = Query<Model>(harness.channel.context);
    final results = await q.fetch();
    expect(results.map((m) => m.name).toList(), ["bob"]);
  });

  test(
      "Calling resetData clears persistent data but retains schema and seeded data",
      () async {
    final q = Query<Model>(harness.channel.context)
      ..sortBy((o) => o.name, QuerySortOrder.ascending);

    await Query.insertObject(harness.channel.context, Model()..name = "fred");
    expect((await q.fetch()).map((m) => m.name).toList(), ["bob", "fred"]);

    await harness.resetData();
    expect((await q.fetch()).map((m) => m.name).toList(), ["bob"]);
  });
}

class Channel extends ApplicationChannel {
  ManagedContext context;

  @override
  Future prepare() async {
    context = ManagedContext(
        ManagedDataModel([Model]),
        PostgreSQLPersistentStore(
            "dart", "dart", "localhost", 5432, "dart_test"));
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router.route("/endpoint").linkFunction((req) async {
      final q = Query<Model>(context);
      return Response.ok(await q.fetch());
    });
    return router;
  }
}

class HarnessSubclass extends TestHarness<Channel> with TestHarnessORMMixin {
  @override
  Future onSetUp() async {
    await resetData();
  }

  @override
  Future seed() async {
    await Query.insertObject(context, Model()..name = "bob");
  }

  @override
  ManagedContext get context => channel.context;
}

class _Model {
  @primaryKey
  int id;

  String name;
}

class Model extends ManagedObject<_Model> implements _Model {}
