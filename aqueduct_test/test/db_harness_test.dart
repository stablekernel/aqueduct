import 'dart:async';

import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  HarnessSubclass harness;

  setUp(() async {
    harness = new HarnessSubclass();
    await harness.setUp();
  });

  tearDown(() async {
    await harness.tearDown();
  });

  test("Calling initializeDatabase uploads schema to channel.context's database", () async {
    expectResponse(await harness.agent.request("endpoint").get(), 200, body: [
      {"id": isNumber, "name": "bob"}
    ]);
  });

  test("Calling resetData clears persistent data but retains schema", () async {
    await harness.resetData();
    expectResponse(await harness.agent.request("endpoint").get(), 200, body: []);
  });
}

class Channel extends ApplicationChannel {
  ManagedContext context;

  @override
  Future prepare() async {
    context = new ManagedContext(
        new ManagedDataModel([Model]), new PostgreSQLPersistentStore("dart", "dart", "localhost", 5432, "dart_test"));
  }

  @override
  Controller get entryPoint {
    final router = new Router();
    router.route("/endpoint").linkFunction((req) async {
      final q = new Query<Model>(context);
      return new Response.ok(await q.fetch());
    });
    return router;
  }
}

class HarnessSubclass extends TestHarness<Channel> with TestHarnessORMMixin {
  @override
  Future afterStart() async {
    await resetData();
  }

  Future seed() async {
    await Query.insertObject(context, new Model()..name = "bob");
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
