import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:postgres/postgres.dart';
import 'dart:async';

void main() {
  PostgreSQLPersistentStore persistentStore = null;

  setUp(() {
    persistentStore = new PostgreSQLPersistentStore(() async {
      var connection = new PostgreSQLConnection("localhost", 5432, "dart_test",
          username: "dart", password: "dart");
      await connection.open();
      return connection;
    });
  });

  tearDown(() async {
    await persistentStore.close();
  });

  test("A down connection will restart", () async {
    var result = await persistentStore.execute("select 1");
    expect(result, [
      [1]
    ]);

    await persistentStore.close();

    result = await persistentStore.execute("select 1");
    expect(result, [
      [1]
    ]);
  });

  test("Ask for multiple connections at once, yield one successful connection",
      () async {
    var connections = await Future.wait([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        .map((_) => persistentStore.getDatabaseConnection()));
    var first = connections.first;
    expect(connections, everyElement(first));
  });

  test("Make multiple requests at once, yield one successful connection",
      () async {
    var expectedValues = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    var values = await Future
        .wait(expectedValues.map((i) => persistentStore.execute("select $i")));

    expect(
        values,
        expectedValues
            .map((v) => [
                  [v]
                ])
            .toList());
  });

  test("Make multiple requests at once, all fail because db connect fails",
      () async {
    persistentStore = new PostgreSQLPersistentStore(() async {
      var connection = new PostgreSQLConnection(
          "localhost", 5432, "xyzxyznotadb",
          username: "dart", password: "dart");
      await connection.open();
      return connection;
    });
    var expectedValues = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    var values = await Future.wait(expectedValues
        .map((i) => persistentStore.execute("select $i").catchError((e) => e)));
    expect(values, everyElement(new isInstanceOf<QueryException>()));
  });

  test(
      "Make multiple requests at once, first few fails because db connect fails (but eventually succeeds)",
      () async {
    var counter = 0;
    persistentStore = new PostgreSQLPersistentStore(() async {
      var conn = (counter == 0
          ? new PostgreSQLConnection("localhost", 5432, "xyzxyznotadb",
              username: "dart", password: "dart")
          : new PostgreSQLConnection("localhost", 5432, "dart_test",
              username: "dart", password: "dart"));
      counter++;
      await conn.open();
      return conn;
    });
    var expectedValues = [1, 2, 3, 4, 5];
    var values = await Future.wait(expectedValues
        .map((i) => persistentStore.execute("select $i").catchError((e) => e)));
    expect(values, everyElement(new isInstanceOf<QueryException>()));

    expectedValues = [5, 6, 7, 8, 9];
    values = await Future
        .wait(expectedValues.map((i) => persistentStore.execute("select $i")));
    expect(
        values,
        expectedValues
            .map((v) => [
                  [v]
                ])
            .toList());
  });
}
