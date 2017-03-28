import 'dart:io';
import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'package:aqueduct/executable.dart';
import '../helpers.dart';
import 'package:postgres/postgres.dart';

void main() {
  group("Generating migration files", () {
    // This group handles checking the tool itself,
    // not the behavior of creating the appropriate migration file given schemas
    var projectSourceDirectory = getTestProjectDirectory("initial");
    Directory projectDirectory = new Directory("test_project");
    var migrationDirectory =
    new Directory.fromUri(projectDirectory.uri.resolve("migrations"));
    var addFiles = (List<String> filenames) {
      filenames.forEach((name) {
        new File.fromUri(migrationDirectory.uri.resolve(name))
            .writeAsStringSync(" ");
      });
    };

    setUp(() async {
      createTestProject(projectSourceDirectory, projectDirectory);
    });

    tearDown(() {
      projectDirectory.deleteSync(recursive: true);
    });

    test("Run without pub get yields error", () async {
      var out = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(out != 0, true);
    });

    test("Ensure migration directory will get created on generation", () async {
      await runPubGet(projectDirectory, offline: true);
      expect(migrationDirectory.existsSync(), false);
      var out = await runAqueductProcess(["db", "generate"], projectDirectory);
      expect(out, 0);
      expect(migrationDirectory.existsSync(), true);
    });

    test(
        "If there are no migration files, create an initial one that validates to schema",
            () async {
          await runPubGet(projectDirectory, offline: true);

          // Putting a non-migration file in there to ensure that this doesn't prevent from being ugpraded
          migrationDirectory.createSync();
          addFiles(["notmigration.dart"]);

          await runAqueductProcess(["db", "generate"], projectDirectory);
          var out = await runAqueductProcess(["db", "validate"], projectDirectory);
          expect(out, 0);
        });

    test("If there is already a migration file, create an upgrade file with changes",
            () async {
          await runPubGet(projectDirectory, offline: true);

          await runAqueductProcess(["db", "generate"], projectDirectory);

          // Let's add an index
          var modelFile = new File.fromUri(projectDirectory.uri.resolve("lib/").resolve("wildfire.dart"));
          var contents = modelFile
            .readAsStringSync()
            .replaceFirst("String foo;", "@ManagedColumnAttributes(indexed: true) String foo;");
          modelFile.writeAsStringSync(contents);

          await runAqueductProcess(["db", "generate"], projectDirectory);

          expect(
              migrationDirectory
                  .listSync()
                  .where((fse) => !fse.uri.pathSegments.last.startsWith(".")),
              hasLength(2));
          expect(
              new File.fromUri(migrationDirectory.uri
                  .resolve("00000001_Initial.migration.dart"))
                  .existsSync(),
              true);
          expect(
              new File.fromUri(migrationDirectory.uri
                  .resolve("00000002_Unnamed.migration.dart"))
                  .existsSync(),
              true);

          var out = await runAqueductProcess(["db", "validate"], projectDirectory);
          expect(out, 0);
        });
  });

  group("Schema diffs", () {
    var migrationDirectory = new Directory("tmp_migrations/migrations");
    PostgreSQLConnection connection;

    setUp(() async {
      connection = new PostgreSQLConnection("localhost", 5432, "dart_test", username: "dart", password: "dart");
      await connection.open();
      migrationDirectory.createSync(recursive: true);
    });

    tearDown(() async {
      migrationDirectory.parent.deleteSync(recursive: true);

      for (var tableName in ["v", "u", "t"]) {
        await connection.execute("DROP TABLE IF EXISTS $tableName");
      }

      await connection.execute("DROP TABLE IF EXISTS _aqueduct_version_pgsql");
      await connection.close();
    });

    /*
    Tables
     */

    test("Table that is new to destination schema emits createTable", () async {
      await writeMigrations(migrationDirectory, [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ])
        ])
      ]);

      await executeMigrations(migrationDirectory.parent);

      var results = await connection.query("INSERT INTO t (id) VALUES (1) RETURNING id");
      expect(results, [[1]]);
    });

    test("Table that is no longer in destination schema emits deleteTable", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ])
        ]),
        new Schema([
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
      ];

      await writeMigrations(migrationDirectory, schemas.sublist(0, 2));
      await executeMigrations(migrationDirectory.parent);

      var results = await connection.query("INSERT INTO t (id) VALUES (1) RETURNING id");
      expect(results, [[1]]);
      results = await connection.query("INSERT INTO u (id) VALUES (1) RETURNING id");
      expect(results, [[1]]);

      await writeMigrations(migrationDirectory, schemas.sublist(1));
      await executeMigrations(migrationDirectory.parent);

      results = await connection.query("INSERT INTO u (id) VALUES (2) RETURNING id");
      expect(results, [[2]]);
      try {
        await connection.query("INSERT INTO t (id) VALUES (1) RETURNING id");
        expect(true, false);
      } on PostgreSQLException catch (e) {
        expect(e.message, contains("relation \"t\" does not exist"));
      }
    });

    test("Two tables to be deleted that are order-dependent because of constraints are added/deleted in the right order", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn.relationship("ref", ManagedPropertyType.integer, relatedTableName: "t", relatedColumnName: "id")
          ]),
        ]),
        new Schema.empty()
      ];
      await writeMigrations(migrationDirectory, schemas.sublist(0, 2));
      await executeMigrations(migrationDirectory.parent);

      // We try and delete this in the wrong order to ensure that when we do delete it,
      // we're actually solving a problem.
      try {
        await connection.execute("DROP TABLE t");
        expect(true, false);
      } on PostgreSQLException catch (e) {
        expect(e.message, contains("cannot drop table t"));
      }

      await writeMigrations(migrationDirectory, schemas.sublist(1));
      await executeMigrations(migrationDirectory.parent);

      try {
        await connection.query("INSERT INTO t (id) VALUES (1) RETURNING id");
        expect(true, false);
      } on PostgreSQLException catch (e) {
        expect(e.message, contains("relation \"t\" does not exist"));
      }

      try {
        await connection.query("INSERT INTO u (id) VALUES (1) RETURNING id");
        expect(true, false);
      } on PostgreSQLException catch (e) {
        expect(e.message, contains("relation \"u\" does not exist"));
      }
    });

    test("Repeat of above, reverse order: Two tables to be added/deleted that are order-dependent because of constraints are deleted in the right order", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn.relationship("ref", ManagedPropertyType.integer, relatedTableName: "t", relatedColumnName: "id")
          ]),
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        new Schema.empty()
      ];

      await writeMigrations(migrationDirectory, schemas);
      await executeMigrations(migrationDirectory.parent);

      try {
        await connection.query("INSERT INTO t (id) VALUES (1) RETURNING id");
        expect(true, false);
      } on PostgreSQLException catch (e) {
        expect(e.message, contains("relation \"t\" does not exist"));
      }

      try {
        await connection.query("INSERT INTO u (id) VALUES (1) RETURNING id");
        expect(true, false);
      } on PostgreSQLException catch (e) {
        expect(e.message, contains("relation \"u\" does not exist"));
      }
    });

    test("Add new table with fkey ref to previous table", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn.relationship("ref", ManagedPropertyType.integer, relatedTableName: "t", relatedColumnName: "id")
          ]),
        ])
      ];

      await writeMigrations(migrationDirectory, schemas);
      await executeMigrations(migrationDirectory.parent);

      await connection.query("INSERT INTO t (id) VALUES (1)");
      var results = await connection.query("INSERT INTO u (id, ref_id) VALUES (1, 1) RETURNING id, ref_id");
      expect(results, [[1, 1]]);
    });

    test("Add new table, and add foreign key to that table from existing table", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        new Schema([
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn.relationship("ref", ManagedPropertyType.integer, relatedTableName: "t", relatedColumnName: "id")
          ]),
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ])
      ];

      await writeMigrations(migrationDirectory, schemas);
      await executeMigrations(migrationDirectory.parent);

      await connection.query("INSERT INTO t (id) VALUES (1)");
      var results = await connection.query("INSERT INTO u (id, ref_id) VALUES (1, 1) RETURNING id, ref_id");
      expect(results, [[1, 1]]);
    });

    /*
     Columns
      */

    test("New column in destination schema emits addColumn", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("x", ManagedPropertyType.integer, isNullable: true)
          ]),
        ])
      ];

      await writeMigrations(migrationDirectory, schemas.sublist(0, 2));
      await executeMigrations(migrationDirectory.parent);

      await connection.query("INSERT INTO t (id) VALUES (1)");
      var results = await connection.query("SELECT * FROM t");
      expect(results, [[1]]);

      await writeMigrations(migrationDirectory, schemas.sublist(1));
      await executeMigrations(migrationDirectory.parent);

      await connection.query("INSERT INTO t (id, x) VALUES (2, 0)");
      results = await connection.query("SELECT * from t ORDER BY id ASC");
      expect(results, [[1, null], [2, 0]]);
    });

    test("New non-nullable column with default value can be upgraded to, default value provided for existing columns", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("x", ManagedPropertyType.integer, isNullable: false, defaultValue: "2")
          ]),
        ])
      ];
      await writeMigrations(migrationDirectory, schemas.sublist(0, 2));
      await executeMigrations(migrationDirectory.parent);

      await connection.query("INSERT INTO t (id) VALUES (1)");

      await writeMigrations(migrationDirectory, schemas.sublist(1));
      await executeMigrations(migrationDirectory.parent);

      await connection.query("INSERT INTO t (id) VALUES (2)");
      await connection.query("INSERT INTO t (id, x) VALUES (3, 0)");
      var results = await connection.query("SELECT * from t ORDER BY id ASC");
      expect(results, [[1, 2], [2, 2], [3, 0]]);
    });

    test("Adding non-nullable column without default value requires initialValue", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("x", ManagedPropertyType.integer, isNullable: false, defaultValue: null)
          ]),
        ])
      ];

      await writeMigrations(migrationDirectory, schemas.sublist(0, 2));
      await executeMigrations(migrationDirectory.parent);
      await connection.query("INSERT INTO t (id) VALUES (1)");
      await writeMigrations(migrationDirectory, schemas.sublist(1));

      // Fails because syntax error for placeholder for unencodedInitialValue
      expect(await executeMigrations(migrationDirectory.parent), greaterThan(0));

      // Update generated source code to add initialValue,
      var lastMigrationFile = new File.fromUri(migrationDirectory.uri.resolve("2.migration.dart"));
      var contents = lastMigrationFile
          .readAsStringSync()
          .replaceFirst(r"<<set>>", "'2'");
      lastMigrationFile.writeAsStringSync(contents);
      expect(await executeMigrations(migrationDirectory.parent), 0);

      await connection.query("INSERT INTO t (id, x) VALUES (2, 3)");
      var results = await connection.query("SELECT id, x FROM t ORDER BY id ASC");
      expect(results, [[1, 2], [2, 3]]);
    });

    test("Add multiple columns in destination schema, emits multiple addColumn", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("x", ManagedPropertyType.integer, isNullable: true),
            new SchemaColumn("y", ManagedPropertyType.string, isNullable: true),
          ]),
        ])
      ];

      await writeMigrations(migrationDirectory, schemas);
      await executeMigrations(migrationDirectory.parent);

      var results = await connection.query("INSERT INTO t (id, x, y) VALUES (1, 2, 'a') RETURNING id, x, y");
      expect(results, [[1, 2, 'a']]);
    });

    test("Remove column from destination schema, emits deleteColumn", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("x", ManagedPropertyType.integer),
            new SchemaColumn("y", ManagedPropertyType.string),
          ]),
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ])
      ];

      await writeMigrations(migrationDirectory, schemas);
      await executeMigrations(migrationDirectory.parent);

      var results = await connection.query("INSERT INTO t (id) VALUES (1) RETURNING id");
      expect(results, [[1]]);

      try {
        await connection.query("INSERT INTO t (id, x, y) VALUES (1, 2, 'a')");
        expect(true, false);
      } on PostgreSQLException catch (e) {
        expect(e.message, contains("column \"x\" of relation \"t\" does not exist"));
      }
    });

    test("Alter column's indexable", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("wasIndexed", ManagedPropertyType.integer, isIndexed: true),
            new SchemaColumn("nowIndexed", ManagedPropertyType.string, isIndexed: false),
          ]),
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("wasIndexed", ManagedPropertyType.integer, isIndexed: false),
            new SchemaColumn("nowIndexed", ManagedPropertyType.string, isIndexed: true),
          ]),
        ]),
      ];

      await writeMigrations(migrationDirectory, schemas);
      await executeMigrations(migrationDirectory.parent);

      var results = await connection.query("SELECT indexname, indexdef FROM pg_indexes where tablename = 't' ORDER BY indexname ASC");
      expect(results.length, 2);
      expect(results[0][0], "t_nowindexed_idx");
      expect(results[0][1], startsWith("CREATE INDEX"));
      expect(results[0][1], endsWith("(nowindexed)"));
      expect(results[1][0], "t_pkey");
      expect(results[1][1], startsWith("CREATE UNIQUE INDEX"));
      expect(results[1][1], endsWith("(id)"));
    });

    test("Alter column's nullability, with default values", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("wasNullable", ManagedPropertyType.integer, isNullable: true),
            new SchemaColumn("nowNullable", ManagedPropertyType.string, isNullable: false),
          ]),
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("wasNullable", ManagedPropertyType.integer, isNullable: false, defaultValue: "2"),
            new SchemaColumn("nowNullable", ManagedPropertyType.string, isNullable: true),
          ]),
        ]),
      ];

      await writeMigrations(migrationDirectory, schemas);
      await executeMigrations(migrationDirectory.parent);

      var results = await connection.query("INSERT INTO t (id) VALUES (1) RETURNING id, wasNullable, nowNullable");
      expect(results, [[1, 2, null]]);
    });

    test("Alter column's nullability, with initial values", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("x", ManagedPropertyType.integer, isNullable: true, defaultValue: null)
          ]),
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("x", ManagedPropertyType.integer, isNullable: false, defaultValue: null)
          ]),
        ])
      ];

      await writeMigrations(migrationDirectory, schemas.sublist(0, 2));
      await executeMigrations(migrationDirectory.parent);
      await connection.query("INSERT INTO t (id) VALUES (1)");
      await connection.query("INSERT INTO t (id, x) VALUES (2, 7)");
      await writeMigrations(migrationDirectory, schemas.sublist(1));

      // Fails because syntax error for placeholder for unencodedInitialValue
      expect(await executeMigrations(migrationDirectory.parent), greaterThan(0));

      // Update generated source code to add initialValue,
      var lastMigrationFile = new File.fromUri(migrationDirectory.uri.resolve("2.migration.dart"));
      var contents = lastMigrationFile
          .readAsStringSync()
          .replaceFirst(r"<<set>>", "'2'");
      lastMigrationFile.writeAsStringSync(contents);
      expect(await executeMigrations(migrationDirectory.parent), 0);

      await connection.query("INSERT INTO t (id, x) VALUES (3, 3)");
      var results = await connection.query("SELECT id, x FROM t ORDER BY id ASC");
      expect(results, [[1, 2], [2, 7], [3, 3]]);
    });

    test("Alter column's uniqueness", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("wasUnique", ManagedPropertyType.integer, isUnique: true),
            new SchemaColumn("nowUnique", ManagedPropertyType.string, isUnique: false),
          ]),
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("wasUnique", ManagedPropertyType.integer, isUnique: false),
            new SchemaColumn("nowUnique", ManagedPropertyType.string, isUnique: true),
          ]),
        ]),
      ];

      await writeMigrations(migrationDirectory, schemas);
      await executeMigrations(migrationDirectory.parent);

      var results = await connection.query("SELECT indexname, indexdef FROM pg_indexes where tablename = 't' ORDER BY indexname ASC");
      expect(results.length, 2);
      expect(results[0][0], "t_nowunique_key");
      expect(results[0][1], startsWith("CREATE UNIQUE INDEX"));
      expect(results[0][1], endsWith("(nowunique)"));
      expect(results[1][0], "t_pkey");
      expect(results[1][1], startsWith("CREATE UNIQUE INDEX"));
      expect(results[1][1], endsWith("(id)"));
    });

    test("Alter column's defaultValue", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("wasDefault", ManagedPropertyType.integer, defaultValue: "2"),
            new SchemaColumn("nowDefault", ManagedPropertyType.string, defaultValue: null),
          ]),
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("wasDefault", ManagedPropertyType.integer, defaultValue: null),
            new SchemaColumn("nowDefault", ManagedPropertyType.string, defaultValue: "'default'"),
          ]),
        ]),
      ];

      await writeMigrations(migrationDirectory, schemas);
      await executeMigrations(migrationDirectory.parent);

      var results = await connection.query("INSERT INTO t (id, wasDefault) VALUES (1, 1) RETURNING id, wasDefault, nowDefault");
      expect(results, [[1, 1, "default"]]);

      try {
        await connection.query("INSERT INTO t (id) VALUES (2)");
        expect(true, false);
      } on PostgreSQLException catch (e) {
        expect(e.message, contains("null value in column \"wasdefault\""));
      }
    });

    test("Alter column's deleteRule", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn.relationship("ref", ManagedPropertyType.integer, relatedTableName: "t", relatedColumnName: "id",
                rule: ManagedRelationshipDeleteRule.nullify)
          ])
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn.relationship("ref", ManagedPropertyType.integer, relatedTableName: "t", relatedColumnName: "id",
                rule: ManagedRelationshipDeleteRule.cascade)
          ])
        ]),
      ];

      await writeMigrations(migrationDirectory, schemas);
      await executeMigrations(migrationDirectory.parent);

      await connection.query("INSERT INTO t (id) VALUES (1)");
      await connection.query("INSERT INTO u (id, ref_id) VALUES (1, 1)");
      await connection.query("DELETE FROM t WHERE id=1");
      var results = await connection.query("SELECT * FROM u");
      expect(results, []);
    });

    test("Alter many properties of a column", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("x", ManagedPropertyType.integer, isNullable: false),
          ]),
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn("x", ManagedPropertyType.integer, isNullable: true, defaultValue: "2"),
          ]),
        ]),
      ];

      await writeMigrations(migrationDirectory, schemas);
      await executeMigrations(migrationDirectory.parent);

      var results = await connection.query("INSERT INTO t (id) VALUES (1) RETURNING id, x");
      expect(results, [[1, 2]]);

      results = await connection.query("INSERT INTO t (id, x) VALUES (2, null) RETURNING id, x");
      expect(results, [[2, null]]);
    });
  });

  group("Invalid operations", () {
    var migrationDirectory = new Directory("tmp_migrations/migrations");

    setUp(() async {
      migrationDirectory.createSync(recursive: true);
    });

    tearDown(() async {
      migrationDirectory.parent.deleteSync(recursive: true);
    });

    test("Cannot add existing table", () async {
      fail("nyi");
    });

    test("Cannot delete unknown table", () async {
      fail("nyi");
    });

    test("Cannot add column to unknown table", () async {
      fail("nyi");
    });

    test("Cannot delete column from unknown table", () async {
      fail("nyi");
    });

    test("Cannot delete unknown column", () async {
      fail("nyi");
    });

    test("Cannot add column to table with existing column of same name", () async {
      fail("nyi");
    });

    test("Cannot change relatedTable", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn.relationship("ref", ManagedPropertyType.integer, relatedTableName: "t", relatedColumnName: "id"),
          ]),
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ]),
        new Schema([
          new SchemaTable("v", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            new SchemaColumn.relationship("ref", ManagedPropertyType.integer, relatedTableName: "v", relatedColumnName: "id"),
          ]),
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ]),
      ];

      try {
        await writeMigrations(migrationDirectory, schemas);
        expect(true, false);
      } catch (e) {
        print("$e");
      }
    });

    test("Cannot change relatedColumn", () async {
      fail("nyi");

    });

    test("Cannot change primaryKey", () async {
      fail("nyi");

    });

    test("Cannot change autoincrement", () async {
      fail("nyi");

    });

    test("Cannot change type", () async {
      fail("nyi");

    });
  });
}

Future<int> runAqueductProcess(
    List<String> commands, Directory workingDirectory) async {
  commands.add("--directory");
  commands.add("${workingDirectory.path}");

  var cmd = new Runner();
  var results = cmd.options.parse(commands);

  return cmd.process(results);
}

Directory getTestProjectDirectory(String name) {
  return new Directory.fromUri(Directory.current.uri
      .resolve("test/command/migration_test_projects/$name"));
}

Future writeMigrations(Directory migrationDirectory, List<Schema> schemas) async {
  var currentNumberOfMigrations = migrationDirectory
    .listSync()
    .where((e) => e.path.endsWith("migration.dart"))
    .length;

  for (var i = 1; i < schemas.length; i++) {
    var source = await MigrationBuilder.sourceForSchemaUpgrade(schemas[i - 1], schemas[i], i);
    var file = new File.fromUri(migrationDirectory.uri.resolve("${i + currentNumberOfMigrations}.migration.dart"));
    file.writeAsStringSync(source);
  }
}

Future<int> executeMigrations(Directory projectDirectory) async {
  return runAqueductProcess(["db", "upgrade", "--connect", "postgres://dart:dart@localhost:5432/dart_test"], projectDirectory);
}
