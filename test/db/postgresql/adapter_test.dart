import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:postgres/postgres.dart';
import 'dart:async';

void main() {
  group("Behavior", () {
    PostgreSQLPersistentStore persistentStore;

    setUp(() async {
      persistentStore = new PostgreSQLPersistentStore("dart", "dart", "localhost", 5432, "dart_test");
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
      persistentStore = new PostgreSQLPersistentStore("dart", "dart", "localhost", 5432, "xyzxyznotadb");
      var expectedValues = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      var values = await Future.wait(expectedValues
          .map((i) => persistentStore.execute("select $i").catchError((e) => e)));
      expect(values, everyElement(new isInstanceOf<QueryException>()));
    });

    test(
        "Make multiple requests at once, first few fails because db connect fails (but eventually succeeds)",
        () async {
      var counter = 0;
      persistentStore = new PostgreSQLPersistentStore("dart", "dart", "localhost", 5432, "xyzxyznotadb");

      new PostgreSQLPersistentStore(() async {
        var connection = (counter == 0
            ? new PostgreSQLConnection("localhost", 5432, "xyzxyznotadb",
                username: "dart", password: "dart")
            : new PostgreSQLConnection("localhost", 5432, "dart_test",
                username: "dart", password: "dart"));
        counter++;
        try {
          await connection.open();
        } catch (e) {
          await connection.close();
        }

        return connection;
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

    test("Connect to bad db fails gracefully, can then be used again", () async {
      persistentStore = new PostgreSQLPersistentStore("dart", "dart", "localhost", 5433, "dart_test");
      try {
        await persistentStore.executeQuery("SELECT 1", null, 20);
        expect(true, false);
      } on QueryException {}

      persistentStore.port = 5432;
      var x = await persistentStore.executeQuery("SELECT 1", null, 20);
      expect(x, [[1]]);
    });
  });

  group("Registration", () {
    test("Create with default constructor registers and handles shutdown", () async {
      var store = new PostgreSQLPersistentStore("dart", "dart", "localhost", 5432, "dart_test");

      await store.execute("SELECT 1");
      expect(store.isConnected, true);

      await ApplicationServiceRegistry.defaultInstance.close();

      expect(store.isConnected, false);
    });
  });
}
