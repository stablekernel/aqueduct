import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:aqueduct/src/db/schema/migration_source.dart';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'cli_helpers.dart';

Terminal terminal;
DatabaseConnectionConfiguration connectInfo =
    new DatabaseConnectionConfiguration.withConnectionInfo("dart", "dart", "localhost", 5432, "dart_test");
String connectString = "postgres://${connectInfo.username}:${connectInfo.password}@${connectInfo.host}:${connectInfo
  .port}/${connectInfo.databaseName}";

void main() {
  PostgreSQLPersistentStore store;

  setUp(() async {
    // create a working directory to store migrations in, inside terminal temporary directory
    store = new PostgreSQLPersistentStore(
        connectInfo.username, connectInfo.password, connectInfo.host, connectInfo.port, connectInfo.databaseName);
    terminal = await Terminal.createProject();
    await terminal.getDependencies(offline: true);
    terminal.defaultMigrationDirectory.createSync();
  });

  tearDown(() async {
    var tables = [
      "_aqueduct_version_pgsql",
      "_foo",
      "_testobject",
    ];

    await Future.wait(tables.map((t) {
      return store.execute("DROP TABLE IF EXISTS $t");
    }));
    await store?.close();

    Terminal.deleteTemporaryDirectory();
  });

  test("Upgrade with no migration files returns 0 exit code", () async {
    expect(await runMigrationCases([]), 0);
    expect(terminal.output, contains("No migration files"));
  });

  test("Generate and execute initial schema makes workable DB", () async {
    expect(await runMigrationCases(["Case1"]), 0);
    var version = await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
    expect(version, [
      [1]
    ]);
    expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
  });

  test("Database already up to date returns 0 status code, does not change version", () async {
    expect(await runMigrationCases(["Case2"]), 0);

    List<List<dynamic>> versionRow =
        await store.execute("SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
    expect(versionRow.first.first, 1);
    var updateDate = versionRow.first.last;

    terminal.clearOutput();
    expect(await runMigrationCases(["Case2"]), 0);
    versionRow = await store.execute("SELECT versionNumber, dateOfUpgrade FROM _aqueduct_version_pgsql");
    expect(versionRow.length, 1);
    expect(versionRow.first.last, equals(updateDate));
    expect(terminal.output, contains("already current (version: 1)"));
  });

  test("Multiple migration files are ran", () async {
    expect(await runMigrationCases(["Case31", "Case32"]), 0);

    var version = await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
    expect(version, [
      [1],
      [2]
    ]);
    expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
    expect(await columnsOfTable(store, "_foo"), ["id", "testobject_id"]);
  });

  test("Only later migration files are ran if already at a version", () async {
    expect(await runMigrationCases(["Case41"]), 0);
    var version = await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
    expect(version, [
      [1]
    ]);
    terminal.clearOutput();

    expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
    expect(await tableExists(store, "_foo"), false);

    expect(await runMigrationCases(["Case42"], fromVersion: 1), 0);
    version = await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
    expect(version, [
      [1],
      [2]
    ]);

    expect(await columnsOfTable(store, "_testobject"), ["id", "foo"]);
    expect(await columnsOfTable(store, "_foo"), ["id", "testobject_id"]);
  });

  test("If migration throws exception, rollback any changes", () async {
    expect(await runMigrationCases(["Case5"]), isNot(0));

    expect(await tableExists(store, store.versionTable.name), false);
    expect(await tableExists(store, "_testobject"), false);
  });

  test("Ensure that the following tests would succeed if the invalid migration were not applied", () async {
    expect(await runMigrationCases(["Case61", "Case63"]), 0);
  });

  test("If migration fails and more migrations are pending, the pending migrations are cancelled", () async {
    expect(await runMigrationCases(["Case61", "Case62", "Case63"]), isNot(0));

    expect(terminal.output.contains("Applied schema version 1 successfully"), true);
    expect(terminal.output, contains("relation \"_unknowntable\" does not exist"));

    expect(await tableExists(store, store.versionTable.name), false);
    expect(await tableExists(store, "_testobject"), false);
    expect(await tableExists(store, "_foo"), false);
  });

  test(
      "If migrations have already been applied, and new migrations occur where the first fails, those pending migrations are cancelled",
      () async {
    expect(await runMigrationCases(["Case61"]), 0);
    expect(terminal.output.contains("Applied schema version 1 successfully"), true);
    terminal.clearOutput();

    expect(await runMigrationCases(["Case62", "Case63"], fromVersion: 1), isNot(0));

    expect(terminal.output, contains("relation \"_unknowntable\" does not exist"));

    final version = await store.execute("SELECT versionNumber FROM _aqueduct_version_pgsql");
    expect(version, [
      [1],
    ]);

    expect(await tableExists(store, store.versionTable.name), true);
    expect(await tableExists(store, "_testobject"), true);
    expect(await tableExists(store, "_foo"), false);
  });

  test("If seed fails, all schema changes are rolled back", () async {
    expect(await runMigrationCases(["Case7"]), isNot(0));

    expect(await tableExists(store, store.versionTable.name), false);
    expect(await tableExists(store, "_testobject"), false);
  });
}

Future<List<String>> columnsOfTable(PersistentStore persistentStore, String tableName) async {
  List<List<String>> results = await persistentStore.execute("select column_name from information_schema.columns where "
      "table_name='$tableName'");
  return results.map((rows) => rows.first).toList();
}

Future<bool> tableExists(PersistentStore store, String tableName) async {
  List<List<dynamic>> exists =
      await store.execute("SELECT to_regclass(@tableName:text)", substitutionValues: {"tableName": tableName});

  return exists.first.first != null;
}

List<MigrationSource> getOrderedTestMigrations(List<String> names, {int fromVersion: 0}) {
  final fileUnit = parseDartFile("test/command/migration_execution_test.dart");

  final migrations = fileUnit.declarations
      .where((u) => u is ClassDeclaration)
      .map((cu) => cu as ClassDeclaration)
      .where((ClassDeclaration classDecl) {
        return classDecl.extendsClause.superclass.name.name == "Migration";
      })
      .map((cu) {
        final code = cu.toSource();
        final offset = cu.name.offset - cu.offset;

        // uri is temporary
        return new MigrationSource(code, Uri.parse("1.migration.dart"), offset, offset + cu.name.length);
      })
      .where((ms) => names.contains(ms.originalName))
      .toList();

  migrations.forEach((ms) {
    final index = names.indexOf(ms.originalName) + 1 + fromVersion;
    ms.uri = Uri.parse("$index.migration.dart");
  });

  return migrations;
}

Future runMigrationCases(List<String> migrationNames, {int fromVersion: 0}) async {
  final migs = getOrderedTestMigrations(migrationNames, fromVersion: fromVersion);

  for (var mig in migs) {
    final file =
        new File.fromUri(terminal.defaultMigrationDirectory.uri.resolve("${mig.versionNumber}_name.migration.dart"));
    file.writeAsStringSync("import 'dart:async';\nimport 'package:aqueduct/aqueduct.dart';\n${mig.source}");
  }

  final res = await terminal.runAqueductCommand("db", [
    "upgrade",
    "--connect",
    connectString
  ]);

  print("${terminal.output}");

  return res;
}

class Case1 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(new SchemaTable(
      "_TestObject",
      [
        new SchemaColumn("id", ManagedPropertyType.bigInteger,
            isPrimaryKey: true, autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn("foo", ManagedPropertyType.string,
            isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case2 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(new SchemaTable(
      "_TestObject",
      [
        new SchemaColumn("id", ManagedPropertyType.bigInteger,
            isPrimaryKey: true, autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn("foo", ManagedPropertyType.string,
            isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case31 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(new SchemaTable(
      "_TestObject",
      [
        new SchemaColumn("id", ManagedPropertyType.bigInteger,
            isPrimaryKey: true, autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn("foo", ManagedPropertyType.string,
            isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case32 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(new SchemaTable(
      "_Foo",
      [
        new SchemaColumn("id", ManagedPropertyType.bigInteger,
            isPrimaryKey: true, autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn.relationship("testObject", ManagedPropertyType.bigInteger,
            relatedTableName: "_TestObject",
            relatedColumnName: "id",
            rule: DeleteRule.nullify,
            isNullable: true,
            isUnique: true),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case41 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(new SchemaTable(
      "_TestObject",
      [
        new SchemaColumn("id", ManagedPropertyType.bigInteger,
            isPrimaryKey: true, autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn("foo", ManagedPropertyType.string,
            isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case42 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(new SchemaTable(
      "_Foo",
      [
        new SchemaColumn("id", ManagedPropertyType.bigInteger,
            isPrimaryKey: true, autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn.relationship("testObject", ManagedPropertyType.bigInteger,
            relatedTableName: "_TestObject",
            relatedColumnName: "id",
            rule: DeleteRule.nullify,
            isNullable: true,
            isUnique: true),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case5 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(new SchemaTable(
      "_TestObject",
      [
        new SchemaColumn("id", ManagedPropertyType.bigInteger,
            isPrimaryKey: true, autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn("foo", ManagedPropertyType.string,
            isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
      ],
    ));
    database.deleteTable("_Foo");
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case61 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(new SchemaTable(
      "_TestObject",
      [
        new SchemaColumn("id", ManagedPropertyType.bigInteger,
            isPrimaryKey: true, autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn("foo", ManagedPropertyType.string,
            isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case62 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(new SchemaTable(
      "_Foo",
      [
        new SchemaColumn("id", ManagedPropertyType.bigInteger,
            isPrimaryKey: true, autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn.relationship("testObject", ManagedPropertyType.bigInteger,
            relatedTableName: "_UnknownTable",
            relatedColumnName: "id",
            rule: DeleteRule.nullify,
            isNullable: true,
            isUnique: true),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case63 extends Migration {
  @override
  Future upgrade() async {
    database.addColumn(
        "_TestObject",
        new SchemaColumn("name", ManagedPropertyType.string,
            isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
        unencodedInitialValue: "0");
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}

class Case7 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(new SchemaTable(
      "_TestObject",
      [
        new SchemaColumn("id", ManagedPropertyType.bigInteger,
            isPrimaryKey: true, autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn("foo", ManagedPropertyType.string,
            isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {
    await database.store.execute("INSERT INTO InvalidTable (foo) VALUES ('foo')");
  }
}
