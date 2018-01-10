import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:postgres/postgres.dart';

void main() {
  group("Metadata", () {
    var store = new PostgreSQLPersistentStore(
        "dart", "dart", "localhost", 5432, "dart_test");

    setUp(() async {});

    tearDown(() async {
      await store.close();
    });

    test(
        "Getting version number with 'blank' database (aka no version table yet) returns 0",
        () async {
      expect(await store.schemaVersion, 0);
    });

    test("Version table gets created on initiating upgrade if it doesn't exist",
        () async {
      await store.upgrade(1, [], temporary: true);

      var rows = await store.execute(
          "SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
      expect(rows.length, 1);
      expect(rows.first.first, 1);
    });

    test(
        "Subsequent upgrades do not fail because the verison table is already created",
        () async {
      await store.upgrade(1, [], temporary: true);
      await store.upgrade(2, [], temporary: true);

      var rows = await store.execute(
          "SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
      expect(rows.length, 2);
      expect(rows.first.first, 1);
      expect(rows.last.first, 2);
    });

    test("Trying to upgrade to version that already exists fails", () async {
      await store.upgrade(1, [], temporary: true);
      try {
        await store.upgrade(1, [], temporary: true);
        expect(true, false);
      } on MigrationException catch (e) {
        expect(e.message, contains("Trying to upgrade database"));
      }
    });

    test("Migration that fails a command does not update", () async {
      await store.upgrade(1, [], temporary: true);
      try {
        await store.upgrade(2, ["CREATE TABLE t (id int)", "invalid command"],
            temporary: true);
        expect(true, false);
      } on QueryException catch (e) {
        expect((e.underlyingException as PostgreSQLException).code, "42601");
      }

      expect(await store.schemaVersion, 1);

      try {
        await store.execute("SELECT id FROM t");
        expect(true, false);
      } on QueryException catch (e) {
        expect((e.underlyingException as PostgreSQLException).code, PostgreSQLErrorCode.undefinedTable);
      }
    });

    test("Version number is dictated by most recent dateOfUpgrade", () async {
      // These are intentionally reversed
      await store.upgrade(2, [], temporary: true);
      await store.upgrade(1, [], temporary: true);

      expect(await store.schemaVersion, 1);
    });
  });
}
