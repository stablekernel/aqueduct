import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:postgresql/postgresql.dart' as postgresql;

void main() {
  test("A down connection will restart", () async {
    var persistentStore = new PostgreSQLPersistentStore(() async {
      var uri = "postgres://dart:dart@localhost:5432/dart_test";
      return await postgresql.connect(uri, timeZone: 'UTC');
    });

    var result = await persistentStore.execute("select 1");
    expect(result, 1);

    await persistentStore.close();
    result = await persistentStore.execute("select 1");
    expect(result, 1);
  });
}
