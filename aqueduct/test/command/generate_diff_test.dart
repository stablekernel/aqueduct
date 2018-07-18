// ignore: unnecessary_const
@Tags(const ["cli"])
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'cli_helpers.dart';

void main() {
  group("Schema diffs", () {
    Terminal terminal;
    PostgreSQLConnection connection;

    setUp(() async {
      connection = PostgreSQLConnection("localhost", 5432, "dart_test",
          username: "dart", password: "dart");
      await connection.open();
      terminal = await Terminal.createProject();
      await terminal.getDependencies();
    });

    tearDown(() async {
      Terminal.deleteTemporaryDirectory();

      for (var tableName in ["v", "u", "t"]) {
        await connection.execute("DROP TABLE IF EXISTS $tableName");
      }

      await connection.execute("DROP TABLE IF EXISTS _aqueduct_version_pgsql");
      await connection.close();
    });

    /*
     Columns
      */

    test("New column in destination schema emits addColumn", () async {
      var schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.integer, isNullable: true)
          ]),
        ])
      ];

      await terminal.writeMigrations(schemas.sublist(0, 2));
      await terminal.executeMigrations();

      await connection.query("INSERT INTO t (id) VALUES (1)");
      var results = await connection.query("SELECT * FROM t");
      expect(results, [
        [1]
      ]);

      await terminal.writeMigrations(schemas.sublist(1));
      await terminal.executeMigrations();

      await connection.query("INSERT INTO t (id, x) VALUES (2, 0)");
      results = await connection.query("SELECT * from t ORDER BY id ASC");
      expect(results, [
        [1, null],
        [2, 0]
      ]);
    });

    test(
        "New non-nullable column with default value can be upgraded to, default value provided for existing columns",
        () async {
      var schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.integer,
                isNullable: false, defaultValue: "2")
          ]),
        ])
      ];
      await terminal.writeMigrations(schemas.sublist(0, 2));
      await terminal.executeMigrations();

      await connection.query("INSERT INTO t (id) VALUES (1)");

      await terminal.writeMigrations(schemas.sublist(1));
      await terminal.executeMigrations();

      await connection.query("INSERT INTO t (id) VALUES (2)");
      await connection.query("INSERT INTO t (id, x) VALUES (3, 0)");
      var results = await connection.query("SELECT * from t ORDER BY id ASC");
      expect(results, [
        [1, 2],
        [2, 2],
        [3, 0]
      ]);
    });

    test(
        "Adding non-nullable column without default value requires initialValue",
        () async {
      var schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.integer,
                isNullable: false, defaultValue: null)
          ]),
        ])
      ];

      await terminal.writeMigrations(schemas.sublist(0, 2));
      await terminal.executeMigrations();
      await connection.query("INSERT INTO t (id) VALUES (1)");
      await terminal.writeMigrations(schemas.sublist(1));

      // Fails because syntax error for placeholder for unencodedInitialValue
      var res = await terminal.executeMigrations();
      expect(res, isNot(0));

      // Update generated source code to add initialValue,
      var lastMigrationFile = File.fromUri(
          terminal.defaultMigrationDirectory.uri.resolve("2.migration.dart"));
      var contents =
          lastMigrationFile.readAsStringSync().replaceFirst(r"<<set>>", "'2'");
      lastMigrationFile.writeAsStringSync(contents);
      res = await terminal.executeMigrations();
      expect(res, 0);

      await connection.query("INSERT INTO t (id, x) VALUES (2, 3)");
      var results =
          await connection.query("SELECT id, x FROM t ORDER BY id ASC");
      expect(results, [
        [1, 2],
        [2, 3]
      ]);
    });

    test("Add multiple columns in destination schema, emits multiple addColumn",
        () async {
      var schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true)
          ]),
        ]),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.integer, isNullable: true),
            SchemaColumn("y", ManagedPropertyType.string, isNullable: true),
          ]),
        ])
      ];

      await terminal.writeMigrations(schemas);
      await terminal.executeMigrations();

      var results = await connection.query(
          "INSERT INTO t (id, x, y) VALUES (1, 2, 'a') RETURNING id, x, y");
      expect(results, [
        [1, 2, 'a']
      ]);
    });

    test("Remove column from destination schema, emits deleteColumn", () async {
      var schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.integer),
            SchemaColumn("y", ManagedPropertyType.string),
          ]),
        ]),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
        ])
      ];

      await terminal.writeMigrations(schemas);
      await terminal.executeMigrations();

      var results =
          await connection.query("INSERT INTO t (id) VALUES (1) RETURNING id");
      expect(results, [
        [1]
      ]);

      try {
        await connection.query("INSERT INTO t (id, x, y) VALUES (1, 2, 'a')");
        expect(true, false);
      } on PostgreSQLException catch (e) {
        expect(e.message,
            contains("column \"x\" of relation \"t\" does not exist"));
      }
    });

    test("Alter column's indexable", () async {
      var schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("wasIndexed", ManagedPropertyType.integer,
                isIndexed: true),
            SchemaColumn("nowIndexed", ManagedPropertyType.string,
                isIndexed: false),
          ]),
        ]),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("wasIndexed", ManagedPropertyType.integer,
                isIndexed: false),
            SchemaColumn("nowIndexed", ManagedPropertyType.string,
                isIndexed: true),
          ]),
        ]),
      ];

      await terminal.writeMigrations(schemas);
      await terminal.executeMigrations();

      var results = await connection.query(
          "SELECT indexname, indexdef FROM pg_indexes where tablename = 't' ORDER BY indexname ASC");
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
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("wasNullable", ManagedPropertyType.integer,
                isNullable: true),
            SchemaColumn("nowNullable", ManagedPropertyType.string,
                isNullable: false),
          ]),
        ]),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("wasNullable", ManagedPropertyType.integer,
                isNullable: false, defaultValue: "2"),
            SchemaColumn("nowNullable", ManagedPropertyType.string,
                isNullable: true),
          ]),
        ]),
      ];

      await terminal.writeMigrations(schemas);
      await terminal.executeMigrations();

      var results = await connection.query(
          "INSERT INTO t (id) VALUES (1) RETURNING id, wasNullable, nowNullable");
      expect(results, [
        [1, 2, null]
      ]);
    });

    test("Alter column's nullability, with initial values", () async {
      var schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.integer,
                isNullable: true, defaultValue: null)
          ]),
        ]),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.integer,
                isNullable: false, defaultValue: null)
          ]),
        ])
      ];

      await terminal.writeMigrations(schemas.sublist(0, 2));
      await terminal.executeMigrations();
      await connection.query("INSERT INTO t (id) VALUES (1)");
      await connection.query("INSERT INTO t (id, x) VALUES (2, 7)");
      await terminal.writeMigrations(schemas.sublist(1));

      // Fails because syntax error for placeholder for unencodedInitialValue
      terminal.clearOutput();
      var res = await terminal.executeMigrations();
      expect(terminal.output, contains("<<set>>"));
      expect(res, isNot(0));

      // Update generated source code to add initialValue,
      var lastMigrationFile = File.fromUri(
          terminal.defaultMigrationDirectory.uri.resolve("2.migration.dart"));
      var contents =
          lastMigrationFile.readAsStringSync().replaceFirst(r"<<set>>", "'2'");
      lastMigrationFile.writeAsStringSync(contents);
      res = await terminal.executeMigrations();
      expect(res, 0);

      await connection.query("INSERT INTO t (id, x) VALUES (3, 3)");
      var results =
          await connection.query("SELECT id, x FROM t ORDER BY id ASC");
      expect(results, [
        [1, 2],
        [2, 7],
        [3, 3]
      ]);
    });

    test("Alter column's uniqueness", () async {
      var schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("wasUnique", ManagedPropertyType.integer,
                isUnique: true),
            SchemaColumn("nowUnique", ManagedPropertyType.string,
                isUnique: false),
          ]),
        ]),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("wasUnique", ManagedPropertyType.integer,
                isUnique: false),
            SchemaColumn("nowUnique", ManagedPropertyType.string,
                isUnique: true),
          ]),
        ]),
      ];

      await terminal.writeMigrations(schemas);
      await terminal.executeMigrations();

      var results = await connection.query(
          "SELECT indexname, indexdef FROM pg_indexes where tablename = 't' ORDER BY indexname ASC");
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
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("wasDefault", ManagedPropertyType.integer,
                defaultValue: "2"),
            SchemaColumn("nowDefault", ManagedPropertyType.string,
                defaultValue: null),
          ]),
        ]),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("wasDefault", ManagedPropertyType.integer,
                defaultValue: null),
            SchemaColumn("nowDefault", ManagedPropertyType.string,
                defaultValue: "'default'"),
          ]),
        ]),
      ];

      await terminal.writeMigrations(schemas);
      await terminal.executeMigrations();

      var results = await connection.query(
          "INSERT INTO t (id, wasDefault) VALUES (1, 1) RETURNING id, wasDefault, nowDefault");
      expect(results, [
        [1, 1, "default"]
      ]);

      try {
        await connection.query("INSERT INTO t (id) VALUES (2)");
        expect(true, false);
      } on PostgreSQLException catch (e) {
        expect(e.message, contains("null value in column \"wasdefault\""));
      }
    });

    test("Alter column's deleteRule", () async {
      var schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn.relationship("ref", ManagedPropertyType.integer,
                relatedTableName: "t",
                relatedColumnName: "id",
                rule: DeleteRule.nullify)
          ])
        ]),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
          ]),
          SchemaTable("u", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn.relationship("ref", ManagedPropertyType.integer,
                relatedTableName: "t",
                relatedColumnName: "id",
                rule: DeleteRule.cascade)
          ])
        ]),
      ];

      await terminal.writeMigrations(schemas);
      await terminal.executeMigrations();

      await connection.query("INSERT INTO t (id) VALUES (1)");
      await connection.query("INSERT INTO u (id, ref_id) VALUES (1, 1)");
      await connection.query("DELETE FROM t WHERE id=1");
      var results = await connection.query("SELECT * FROM u");
      expect(results, []);
    });

    test("Alter many properties of a column", () async {
      var schemas = [
        Schema.empty(),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.integer, isNullable: false),
          ]),
        ]),
        Schema([
          SchemaTable("t", [
            SchemaColumn("id", ManagedPropertyType.integer, isPrimaryKey: true),
            SchemaColumn("x", ManagedPropertyType.integer,
                isNullable: true, defaultValue: "2"),
          ]),
        ]),
      ];

      await terminal.writeMigrations(schemas);
      await terminal.executeMigrations();

      var results = await connection
          .query("INSERT INTO t (id) VALUES (1) RETURNING id, x");
      expect(results, [
        [1, 2]
      ]);

      results = await connection
          .query("INSERT INTO t (id, x) VALUES (2, null) RETURNING id, x");
      expect(results, [
        [2, null]
      ]);
    });
  });
}
