import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'dart:io';

void main() {
  PostgreSQLPersistentStore store;
  var tablesToDelete = [];
  setUp(() {
    store = new PostgreSQLPersistentStore.fromConnectionInfo("dart", "dart", "localhost", 5432, "dart_test");
    new Directory("${Directory.current.path}/tmp").createSync();
  });

  tearDown(() async {
    new Directory("${Directory.current.path}/tmp").deleteSync(recursive: true);
    await store.execute("DROP TABLE _aqueduct_version_pgsql");
    for (var t in tablesToDelete) {
      await store.execute("DROP TABLE $t");
    }
    await store.close();
  });

  test("Empty schema to schema with tables", () async {
    tablesToDelete = ["t1, t2"];

    var s1 = new Schema.empty();
    var s2 = new Schema([
      new SchemaTable("t1", [
        new SchemaColumn("c1", PropertyType.integer, isPrimaryKey: true),
        new SchemaColumn("c2", PropertyType.string, isIndexed: true, defaultValue: "'foo'")
      ]),
      new SchemaTable("t2", [
        new SchemaColumn("c1", PropertyType.integer, isPrimaryKey: true),
      ]),
    ]);
    var source = SchemaBuilder.sourceForSchemaUpgrade(s1, s2, 1);

    new File("${Directory.current.path}/tmp/1_initial.migration.dart").writeAsStringSync(source);

    var executor = new MigrationExecutor(store, new Uri.file("${Directory.current.path}/tmp"));
    var outSchema = await executor.upgrade();
    expect(outSchema.matches(s2), true);

    expect(await executor.persistentStore.execute("select * from t1"), []);
    expect(await executor.persistentStore.execute("select * from t2"), []);
    expect(await store.schemaVersion, 1);
  });
}