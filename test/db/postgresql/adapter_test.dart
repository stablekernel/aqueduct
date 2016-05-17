import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:postgresql/postgresql.dart' as postgresql;

void main() {
  PostgresModelAdapter adapter;

  setUp(() async {
    adapter = new PostgresModelAdapter(null, () async {
      var uri = 'postgres://dart:dart@localhost:5432/dart_test';
      return await postgresql.connect(uri, timeZone: 'UTC');
    });
  });

  tearDown(() {
    adapter.close();
    adapter = null;
  });

  test("Connection is lazily loaded async", () async {});

  test("Connection times out when reaching max", () async {
    /*
    await generateTemporarySchemaFromModels(adapter, [TestModel]);

    var m = new TestModel()
      ..name.value = "bob"
      ..emailAddress.value = "timeout@a.com";

    var insertReq = new Request.forInsert(TestModel)
      ..returnsInsertedOrUpdatedObjects = false
      ..timeoutInSeconds = 0
      ..valueObject = m;

    try {
      await insertReq.execute(adapter);
      fail("Request should have timed out");
    } catch (e) {
      expect(e.statusCode, 503);
      expect(e.errorCode, -1);
      expect((e as RequestException).message, equals("Request Timeout"));
    }*/
  });

  test("A down connection will restart", () async {
    /*
    adapter.close();

    var m = new TestModel()
      ..name.value = "bob"
      ..emailAddress.value = "restart@a.com";

    var req = new Request.forInsert(TestModel)
      ..valueObject = m;

    try {
      await req.execute(adapter);
      fail(
        "The connection shouldn't succeed because the temporary table would be destroyed, it should fail with a specific error message.");
    } catch (e) {
      expect(e.message, 'relation "simple" does not exist');
    }*/
  });
}
