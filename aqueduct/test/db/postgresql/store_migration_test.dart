import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  group("Metadata", () {
    var store = PostgreSQLPersistentStore(
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
      await store.upgrade(Schema.empty(), [EmptyMigration()..version = 1],
          temporary: true);

      var rows = await store.execute(
          "SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
      expect(rows.length, 1);
      expect(rows.first.first, 1);
    });

    test(
        "Subsequent upgrades do not fail because the verison table is already created",
        () async {
      final s1 = await store.upgrade(
          Schema.empty(), [EmptyMigration()..version = 1],
          temporary: true);
      await store.upgrade(s1, [EmptyMigration()..version = 2], temporary: true);

      var rows = await store.execute(
          "SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
      expect(rows.length, 2);
      expect(rows.first.first, 1);
      expect(rows.last.first, 2);
    });

    test("Trying to upgrade to version that already exists fails", () async {
      final s1 = await store.upgrade(
          Schema.empty(), [EmptyMigration()..version = 1],
          temporary: true);
      try {
        await store.upgrade(s1, [EmptyMigration()..version = 1],
            temporary: true);
        expect(true, false);
      } on MigrationException catch (e) {
        expect(e.message, contains("Trying to upgrade database"));
      }
    });

    test(
        "Trying to upgrade to version that is earlier than latest migration fails",
        () async {
      final s1 = await store.upgrade(
          Schema.empty(), [EmptyMigration()..version = 2],
          temporary: true);
      try {
        await store.upgrade(s1, [EmptyMigration()..version = 1],
            temporary: true);
        expect(true, false);
      } on MigrationException catch (e) {
        expect(e.message, contains("Trying to upgrade database"));
      }

      expect(await store.schemaVersion, 2);
    });

    test("Apply more than one migration to new database", () async {
      await store.upgrade(Schema.empty(),
          [EmptyMigration()..version = 1, EmptyMigration()..version = 2],
          temporary: true);
      expect(await store.schemaVersion, 2);
    });

    test("Apply more than one migration to existing database", () async {
      await store.upgrade(Schema.empty(),
          [EmptyMigration()..version = 1, EmptyMigration()..version = 2],
          temporary: true);
      expect(await store.schemaVersion, 2);
      await store.upgrade(Schema.empty(),
          [EmptyMigration()..version = 3, EmptyMigration()..version = 4],
          temporary: true);
      expect(await store.schemaVersion, 4);
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
