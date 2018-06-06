@Timeout(const Duration(seconds: 45))

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'cli_helpers.dart';
import 'package:postgres/postgres.dart';

void main() {
  group("Schema diffs", () {
    Terminal terminal;
    PostgreSQLConnection connection;

    setUp(() async {
      connection = new PostgreSQLConnection("localhost", 5432, "dart_test",
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
    Tables
     */

    test("Table that is new to destination schema emits createTable", () async {
      await terminal.writeMigrations([
        new Schema.empty(),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer,
                isPrimaryKey: true)
          ])
        ])
      ]);

      await terminal.executeMigrations();

      var results =
      await connection.query("INSERT INTO t (id) VALUES (1) RETURNING id");
      expect(results, [
        [1]
      ]);
    });

    test("Table that is no longer in destination schema emits deleteTable",
            () async {
          var schemas = [
            new Schema.empty(),
            new Schema([
              new SchemaTable("u", [
                new SchemaColumn("id", ManagedPropertyType.integer,
                    isPrimaryKey: true)
              ]),
              new SchemaTable("t", [
                new SchemaColumn("id", ManagedPropertyType.integer,
                    isPrimaryKey: true)
              ])
            ]),
            new Schema([
              new SchemaTable("u", [
                new SchemaColumn("id", ManagedPropertyType.integer,
                    isPrimaryKey: true)
              ]),
            ]),
          ];

          await terminal.writeMigrations(schemas.sublist(0, 2));
          await terminal.executeMigrations();

          var results =
          await connection.query("INSERT INTO t (id) VALUES (1) RETURNING id");
          expect(results, [
            [1]
          ]);
          results =
          await connection.query("INSERT INTO u (id) VALUES (1) RETURNING id");
          expect(results, [
            [1]
          ]);

          await terminal.writeMigrations(schemas.sublist(1));
          await terminal.executeMigrations();

          results =
          await connection.query("INSERT INTO u (id) VALUES (2) RETURNING id");
          expect(results, [
            [2]
          ]);
          try {
            await connection.query("INSERT INTO t (id) VALUES (1) RETURNING id");
            expect(true, false);
          } on PostgreSQLException catch (e) {
            expect(e.message, contains("relation \"t\" does not exist"));
          }
        });

    test(
        "Two tables to be deleted that are order-dependent because of constraints are added/deleted in the right order",
            () async {
          var schemas = [
            new Schema.empty(),
            new Schema([
              new SchemaTable("t", [
                new SchemaColumn("id", ManagedPropertyType.integer,
                    isPrimaryKey: true)
              ]),
              new SchemaTable("u", [
                new SchemaColumn("id", ManagedPropertyType.integer,
                    isPrimaryKey: true),
                new SchemaColumn.relationship("ref", ManagedPropertyType.integer,
                    relatedTableName: "t", relatedColumnName: "id")
              ]),
            ]),
            new Schema.empty()
          ];
          await terminal.writeMigrations(schemas.sublist(0, 2));
          await terminal.executeMigrations();

          // We try and delete this in the wrong order to ensure that when we do delete it,
          // we're actually solving a problem.
          try {
            await connection.execute("DROP TABLE t");
            expect(true, false);
          } on PostgreSQLException catch (e) {
            expect(e.message, contains("cannot drop table t"));
          }

          await terminal.writeMigrations(schemas.sublist(1));
          await terminal.executeMigrations();

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

    test(
        "Repeat of above, reverse order: Two tables to be added/deleted that are order-dependent because of constraints are deleted in the right order",
            () async {
          var schemas = [
            new Schema.empty(),
            new Schema([
              new SchemaTable("u", [
                new SchemaColumn("id", ManagedPropertyType.integer,
                    isPrimaryKey: true),
                new SchemaColumn.relationship("ref", ManagedPropertyType.integer,
                    relatedTableName: "t", relatedColumnName: "id")
              ]),
              new SchemaTable("t", [
                new SchemaColumn("id", ManagedPropertyType.integer,
                    isPrimaryKey: true)
              ]),
            ]),
            new Schema.empty()
          ];

          await terminal.writeMigrations(schemas);
          await terminal.executeMigrations();

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
            new SchemaColumn("id", ManagedPropertyType.integer,
                isPrimaryKey: true)
          ]),
        ]),
        new Schema([
          new SchemaTable("t", [
            new SchemaColumn("id", ManagedPropertyType.integer,
                isPrimaryKey: true)
          ]),
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer,
                isPrimaryKey: true),
            new SchemaColumn.relationship("ref", ManagedPropertyType.integer,
                relatedTableName: "t", relatedColumnName: "id")
          ]),
        ])
      ];

      await terminal.writeMigrations(schemas);
      await terminal.executeMigrations();

      await connection.query("INSERT INTO t (id) VALUES (1)");
      var results = await connection.query(
          "INSERT INTO u (id, ref_id) VALUES (1, 1) RETURNING id, ref_id");
      expect(results, [
        [1, 1]
      ]);
    });

    test("Add new table, and add foreign key to that table from existing table",
            () async {
          var schemas = [
            new Schema.empty(),
            new Schema([
              new SchemaTable("u", [
                new SchemaColumn("id", ManagedPropertyType.integer,
                    isPrimaryKey: true)
              ]),
            ]),
            new Schema([
              new SchemaTable("u", [
                new SchemaColumn("id", ManagedPropertyType.integer,
                    isPrimaryKey: true),
                new SchemaColumn.relationship("ref", ManagedPropertyType.integer,
                    relatedTableName: "t", relatedColumnName: "id")
              ]),
              new SchemaTable("t", [
                new SchemaColumn("id", ManagedPropertyType.integer,
                    isPrimaryKey: true),
              ]),
            ])
          ];

          await terminal.writeMigrations(schemas);
          await terminal.executeMigrations();

          await connection.query("INSERT INTO t (id) VALUES (1)");
          var results = await connection.query(
              "INSERT INTO u (id, ref_id) VALUES (1, 1) RETURNING id, ref_id");
          expect(results, [
            [1, 1]
          ]);
        });

    test("Add unique constraint to table", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer,
                isPrimaryKey: true),
            new SchemaColumn("a", ManagedPropertyType.integer)
          ]),
        ]),
        new Schema([
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer,
                isPrimaryKey: true),
            new SchemaColumn("a", ManagedPropertyType.integer),
            new SchemaColumn("b", ManagedPropertyType.integer, isNullable: true),
          ], uniqueColumnSetNames: ["a", "b"]),
        ])
      ];

      await terminal.writeMigrations(schemas);
      await terminal.executeMigrations();

      await connection.query("INSERT INTO u (id,a,b) VALUES (1,1,1)");
      try {
        await connection.query("INSERT INTO u (id,a,b) VALUES (2,1,1)");
        expect(true, false);
      } on PostgreSQLException catch (e) {
        expect(e.message, contains("duplicate key value violates unique constraint \"u_unique_idx\""));
      }
    });

    test("Remove unique constraint from table", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer,
                isPrimaryKey: true),
            new SchemaColumn("a", ManagedPropertyType.integer),
            new SchemaColumn("b", ManagedPropertyType.integer)
          ], uniqueColumnSetNames: ["a","b"]),
        ]),
        new Schema([
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer,
                isPrimaryKey: true),
            new SchemaColumn("a", ManagedPropertyType.integer),
            new SchemaColumn("b", ManagedPropertyType.integer),
          ]),
        ])
      ];

      await terminal.writeMigrations(schemas);
      await terminal.executeMigrations();

      await connection.query("INSERT INTO u (id,a,b) VALUES (1,1,1)");
      var y = await connection.query("INSERT INTO u (id,a,b) VALUES (2,1,1)");
      expect(y, isNotNull);
    });

    test("Modify unique constraint on table", () async {
      var schemas = [
        new Schema.empty(),
        new Schema([
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer,
                isPrimaryKey: true),
            new SchemaColumn("a", ManagedPropertyType.integer),
            new SchemaColumn("b", ManagedPropertyType.integer)
          ], uniqueColumnSetNames: ["a","b"]),
        ]),
        new Schema([
          new SchemaTable("u", [
            new SchemaColumn("id", ManagedPropertyType.integer,
                isPrimaryKey: true),
            new SchemaColumn("a", ManagedPropertyType.integer),
            new SchemaColumn("b", ManagedPropertyType.integer),
            new SchemaColumn("c", ManagedPropertyType.integer, isNullable: true)
          ], uniqueColumnSetNames: ["b", "c"]),
        ])
      ];

      await terminal.writeMigrations(schemas);
      await terminal.executeMigrations();

      await connection.query("INSERT INTO u (id,a,b,c) VALUES (1,1,1,1)");
      var y = await connection.query("INSERT INTO u (id,a,b,c) VALUES (2,1,1,2)");
      expect(y, isNotNull);

      try {
        await connection.query("INSERT INTO u (id,a,b,c) VALUES (3,5,1,1)");
        expect(true, false);
      } on PostgreSQLException catch (e) {
        expect(e.message, contains("duplicate key value violates unique constraint \"u_unique_idx\""));
      }
    });
  });
}