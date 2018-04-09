import 'dart:async';

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
      await store.upgrade(new Schema.empty(), 1, new EmptyMigration(), temporary: true);

      var rows = await store.execute(
          "SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
      expect(rows.length, 1);
      expect(rows.first.first, 1);
    });

    test(
        "Subsequent upgrades do not fail because the verison table is already created",
        () async {
      final s1 = await store.upgrade(new Schema.empty(), 1, new EmptyMigration(), temporary: true);
      await store.upgrade(s1, 2, new EmptyMigration(), temporary: true);

      var rows = await store.execute(
          "SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
      expect(rows.length, 2);
      expect(rows.first.first, 1);
      expect(rows.last.first, 2);
    });

    test("Trying to upgrade to version that already exists fails", () async {
      final s1 = await store.upgrade(new Schema.empty(), 1, new EmptyMigration(), temporary: true);
      try {
        await store.upgrade(s1, 1, new EmptyMigration(), temporary: true);
        expect(true, false);
      } on MigrationException catch (e) {
        expect(e.message, contains("Trying to upgrade database"));
      }
    });

    test("Version number is dictated by most recent dateOfUpgrade", () async {
      // These are intentionally reversed
      final s = await store.upgrade(new Schema.empty(), 2, new EmptyMigration(), temporary: true);
      await store.upgrade(s, 1, new EmptyMigration(), temporary: true);

      expect(await store.schemaVersion, 1);
    });
  });
}

class EmptyMigration extends Migration {
  @override
  Future upgrade() async => null;

  @override
  Future seed() async => null;

  @override
  Future downgrade() async => null;

}